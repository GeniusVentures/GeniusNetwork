---
phase: tokenprice-quick-261009-oxi
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - SuperGenius/pricecoordinator/src/upstream.ts
  - SuperGenius/pricecoordinator/test/key.test.ts
autonomous: false          # NO-COMMIT HOLD — user verifies locally (wrangler dev + browser) before any commit
requirements: [Q-261009-OXI]

estimate:
  tokens: 18000
  raw_tokens: 12000
  tasks: 2
  confidence: med

must_haves:
  truths:
    - Every outbound GET to https://api.coingecko.com/api/v3/simple/price from the worker carries the constant descriptive User-Agent "GNUS-PriceCoordinator/1.0 (https://token.gnus.ai)" — on the keyed path AND the anonymous path
    - The x-cg-demo-api-key binding behavior is byte-identical to before (header present iff env.COINGECKO_API_KEY is set; key read only in fetchUpstream)
    - Both gates pass from repo root: npm --prefix SuperGenius/pricecoordinator run test and npm --prefix SuperGenius/pricecoordinator run typecheck
    - The change is verifiable locally via wrangler dev + browser before anything is committed (user sequencing decision, 2026-10-09)
  artifacts:
    - SuperGenius/pricecoordinator/src/upstream.ts — unconditional User-Agent constant on the upstream fetch
    - SuperGenius/pricecoordinator/test/key.test.ts — additive UA-presence assertions at the msw seam
  key_links:
    - fetchUpstream header construction → outbound fetch(url, { headers, signal }) — the UA must reach the wire, not just the headers object
    - test/key.test.ts msw http.get(UPSTREAM) handler → request.headers.get("User-Agent") — UA observable in both env variants
---

<objective>
Fix the live 403 from CoinGecko on the price coordinator (local `wrangler dev` AND deployed worker) by sending a descriptive User-Agent header on every upstream `/simple/price` request.

Purpose: CoinGecko now hard-requires a descriptive User-Agent on `/api/v3/simple/price` (live-verified 2026-10-09 from a residential IP: curl WITH its UA → 200; UA stripped → 403 with `{"status":{"error_code":403,"error_message":"Please add a descriptive User-Agent to your request..."}}`; `/ping` returns 200 either way). Cloudflare Workers `fetch` sends NO User-Agent unless explicitly set, and `fetchUpstream` builds an empty `headers` map unless `env.COINGECKO_API_KEY` is set — so every worker request is UA-less and 403s (`502 upstream_error, coinGecko responded 403` on price-coordinator.yellow-snow-2071.workers.dev). This also empirically resolves the deferred tokenprice item "Phase 02 live WAF/UA comparison and real 403 response — partial": the operative gate is the UA requirement, not only IP reputation.

Output: two modified files (src/upstream.ts, test/key.test.ts), gates green, working tree ready for the user's local verification.

## ⚠ EXECUTION NOTES — READ FIRST

**NO-COMMIT HOLD (user sequencing decision, 2026-10-09):** Do NOT run `git commit` at any point during this plan — not in the SuperGenius submodule checkout, not in the outer GeniusNetwork repo. The user tests the change LOCALLY before anything is committed. Standard per-task commit steps from execute-plan.md are SUSPENDED for this run.

Sequence: complete both tasks → run both gates → STOP and return to the orchestrator with a handoff note. The orchestrator pauses for user local verification:

1. `npm --prefix SuperGenius/pricecoordinator run dev` (wrangler dev)
2. Browser GET `http://localhost:8787/v1/prices?ids=gnus&vs=usd` — expect a 200 prices envelope, not `502 upstream_error`

Commit happens only after the user confirms. Deployment to the live worker (per SuperGenius/pricecoordinator/DEPLOYMENT.md) is a post-commit follow-up and is explicitly OUT OF SCOPE here.

**Scope fence:** modify ONLY the two files in `files_modified`. Do not touch wrangler.jsonc, DEPLOYMENT.md, or any other file. The UA string contains a public product URL only.
</objective>

<execution_context>
@~/.copilot/gsd-core/workflows/execute-plan.md
@~/.copilot/gsd-core/templates/summary.md
</execution_context>

<context>
@.planning/workstreams/tokenprice/STATE.md
@SuperGenius/pricecoordinator/src/upstream.ts
@SuperGenius/pricecoordinator/test/key.test.ts
</context>

<tasks>

<task type="auto">
  <name>Task 1: Always send descriptive User-Agent from fetchUpstream</name>
  <files>SuperGenius/pricecoordinator/src/upstream.ts</files>
  <action>
In SuperGenius/pricecoordinator/src/upstream.ts, inside fetchUpstream, directly after `const headers: Record<string, string> = {};`, unconditionally set `headers["User-Agent"] = UPSTREAM_USER_AGENT;` where UPSTREAM_USER_AGENT is a new exported module-level string constant with the exact value `GNUS-PriceCoordinator/1.0 (https://token.gnus.ai)`. It must be sent with AND without env.COINGECKO_API_KEY — place it BEFORE the existing `if (env.COINGECKO_API_KEY)` block, and leave that block and its D-04/D-05 comment untouched so the key binding logic stays byte-identical. Export the constant so the test can import it (single source of truth, no string drift).

Update the header-building comment block: state that CoinGecko hard-403s /simple/price requests lacking a descriptive User-Agent (live-verified 2026-10-09) and that Cloudflare Workers fetch sends no User-Agent unless explicitly set — hence the constant on every call. Keep the existing `// No Accept-Encoding header` line as-is.

Do not change the URL construction, AbortController/timeout logic (KF-11), status-before-parse ordering (T-01-06), row filtering (D-09), or UpstreamError. Per the objective's NO-COMMIT HOLD: after typecheck passes, stage nothing — commit is withheld until the user confirms local verification.
  </action>
  <verify>
    <automated>npm --prefix SuperGenius/pricecoordinator run typecheck</automated>
  </verify>
  <done>upstream.ts exports UPSTREAM_USER_AGENT with the exact value GNUS-PriceCoordinator/1.0 (https://token.gnus.ai); fetchUpstream sets headers["User-Agent"] on every call regardless of key presence; the keyed-path block and all surrounding logic are unchanged; typecheck passes; no commit exists for this change.</done>
</task>

<task type="auto">
  <name>Task 2: Assert User-Agent on the upstream request in both keyed and anonymous paths</name>
  <files>SuperGenius/pricecoordinator/test/key.test.ts</files>
  <action>
In SuperGenius/pricecoordinator/test/key.test.ts, add ONE new `it(...)` inside the existing `describe("x-cg-demo-api-key binding (D-04/D-05) — fetchUpstream seam", ...)`: "sends a descriptive User-Agent on every upstream request — keyed and anonymous". Follow the file's established msw pattern: `network.use(http.get(UPSTREAM, ({ request }) => { uaSeen = request.headers.get("User-Agent"); return HttpResponse.json({ ... }); }))`. Call fetchUpstream twice — first with the keyed env (`{ ...env, COINGECKO_API_KEY: "test-key-123" } as Env`), then with the anonymous env (existing destructure-omit pattern for COINGECKO_API_KEY) — capturing `uaSeen` before each await. Assert both captures `.toBe(UPSTREAM_USER_AGENT)` using the constant imported from `../src/upstream` (add it to the existing import line), so the assertion pins the exact shipped string. Use distinct mock row ids per call so both rows are asserted.

Keep every existing assertion intact and unmodified: the two `seen` x-cg-demo-api-key checks (present-when-set / null-when-unset), the end-to-end no-leak test, and the KF-11 timeout test. The new test is purely additive. Per the objective's NO-COMMIT HOLD: after the test gate passes, return to the orchestrator with the local-verification handoff (wrangler dev + browser GET http://localhost:8787/v1/prices?ids=gnus&vs=usd expecting 200) — commit is withheld until the user confirms.
  </action>
  <verify>
    <automated>npm --prefix SuperGenius/pricecoordinator run test</automated>
  </verify>
  <done>The new test asserts request.headers.get("User-Agent") equals the imported UPSTREAM_USER_AGENT constant for both the keyed and anonymous fetchUpstream calls and passes; the pre-existing key/no-key and no-leak assertions are byte-identical; full suite passes; no commit exists for this change.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| worker → CoinGecko API | outbound fetch to api.coingecko.com carries service-identifying UA header |
| client → worker | unchanged by this plan (response shape untouched) |

## STRIDE Threat Register

Unique IDs within this quick phase; SC slot reserved per convention.

| Threat ID | Category | Component | Severity | Disposition | Mitigation Plan |
|-----------|----------|-----------|----------|-------------|-----------------|
| T-261009-oxi-01 | Denial of Service | fetchUpstream (worker → CoinGecko) | high | mitigate | UA-less requests are hard-403'd by CoinGecko, killing the tier-2 price feed everywhere; Task 1 sends the descriptive UA on every call (keyed and anonymous) — the direct fix |
| T-261009-oxi-02 | Information Disclosure | UPSTREAM_USER_AGENT constant | low | accept | The UA deliberately identifies the service per CoinGecko's requirement; it exposes a public product URL only — no internals, no keys, no operator details beyond a coarse /1.0 |
| T-261009-oxi-03 | Tampering | src/upstream.ts keyed-path block | medium | mitigate | An accidental edit to the D-04/D-05 key binding could change auth behavior under cover of a "header fix"; Task 1's fenced scope (constant placed before the existing if-block, block untouched) plus Task 2 keeping the existing key/no-key assertions intact locks the binding to byte-identical behavior |
| T-261009-oxi-SC | Tampering | npm/pip/cargo installs | high | mitigate | Zero package installs planned (devDependencies already satisfy everything); if the executor finds itself needing `npm install` for any reason, STOP — package-legitimacy gate + blocking human checkpoint apply and auto_advance is ignored |
</threat_model>

<verification>
From repo root (cwd = checkout root), after both tasks:

1. `npm --prefix SuperGenius/pricecoordinator run test` — full vitest suite green, including the new UA assertions and all pre-existing key/no-key/no-leak tests.
2. `npm --prefix SuperGenius/pricecoordinator run typecheck` — both tsconfig projects (src + test) compile clean.
3. `git -C SuperGenius status --porcelain` shows ONLY `M pricecoordinator/src/upstream.ts` and `M pricecoordinator/test/key.test.ts` — confirms the scope fence (wrangler.jsonc, DEPLOYMENT.md untouched) and that both edits live in the SuperGenius checkout awaiting user verification.
4. `git -C SuperGenius log --oneline -1` still shows the pre-plan HEAD (0fd1de762 lineage) — confirms the NO-COMMIT HOLD held.

Then STOP — orchestrator pauses for user local verification (`npm --prefix SuperGenius/pricecoordinator run dev`, browser GET `http://localhost:8787/v1/prices?ids=gnus&vs=usd`, expect 200 prices envelope). Commit (submodule first, then outer repo) only after the user confirms.
</verification>

<success_criteria>
- CoinGecko `/simple/price` requests from the worker carry User-Agent `GNUS-PriceCoordinator/1.0 (https://token.gnus.ai)` on keyed and anonymous paths alike — proven by the imported-constant msw assertions.
- Key binding (D-04/D-05), timeout (KF-11), status-before-parse (T-01-06), and row filtering (D-09) behavior are unchanged — existing assertions untouched and green.
- Both gates pass from repo root; only the two permitted files are modified; zero commits created.
- User has verified locally via wrangler dev + browser and has given the commit go-ahead (orchestrator-gated).
</success_criteria>

<output>
Do NOT create the SUMMARY yet. After the user confirms local verification and the orchestrator commits, create `.planning/workstreams/tokenprice/quick/261009-oxi-add-user-agent-header-to-price-coordinat/261009-oxi-SUMMARY.md` recording: the UA fix, both gate results, the user's local verification result, and the note that this empirically resolves the deferred Phase 02 WAF/UA item (operative gate = UA requirement). Live redeploy (DEPLOYMENT.md runbook) is the post-commit follow-up.
</output>
