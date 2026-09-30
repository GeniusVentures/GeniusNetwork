---
phase: 01-token-gnus-ai-worker-service
plan: 01
subsystem: infra
tags: [cloudflare-workers, wrangler, vitest, durable-objects, msw, testing, npm]

requires:
  - phase: none
    provides: greenfield — first plan of the workstream
provides:
  - "Self-contained npm project at SuperGenius/pricecoordinator/ (D-01/D-02) with npm ci/typecheck/test all green"
  - "wrangler.jsonc with PRICE_COORDINATOR SQLite-DO binding + new_sqlite_classes migration v1 (SRVC-03/SRVC-07 config half)"
  - "vitest-in-workerd harness: cloudflareTest plugin, MSW network instance, fail-closed outboundService egress guard (TEST-01 bootstrap)"
  - "Proven MSW-vs-outboundService layering: mocked fetches answered inside workerd; unmocked → 599 egress_blocked"
  - "Stub DO class (coordinator.ts) and worker entry (index.ts with Env interface) for plans 01-02..01-05"
affects: [01-02 router, 01-03 DO, 01-04 cache, 01-05 full suite, phase-5 worker-tests CI]

tech-stack:
  added:
    - "@cloudflare/vitest-plugin@1.2.4 (downgraded from planned ^1.3.3 — see deviations)"
    - "wrangler@4.137.0 (^4.136.3 pin)"
    - "vitest@4.1.11 (^4.1.0 — 4.x pin held)"
    - "msw@2.15.0 + @msw/cloudflare@0.0.1 (downgraded from ^3.0.0/^0.2.0)"
    - "@cloudflare/workers-types@5.20260923.1"
    - "typescript@5.9.3 (~5.9.0 tilde pin held — NOT 7.x)"
  patterns:
    - "Scoped subdirectory .gitignore instead of touching SuperGenius/.gitignore (Landmine 13)"
    - "outboundService fail-closed egress guard as the hermeticity primitive (KF-2/KF-13)"
    - "Dual tsconfig projects: src + test with different `types` arrays"

key-files:
  created:
    - SuperGenius/pricecoordinator/package.json
    - SuperGenius/pricecoordinator/package-lock.json
    - SuperGenius/pricecoordinator/wrangler.jsonc
    - SuperGenius/pricecoordinator/tsconfig.json
    - SuperGenius/pricecoordinator/vitest.config.ts
    - SuperGenius/pricecoordinator/.gitignore
    - SuperGenius/pricecoordinator/src/index.ts
    - SuperGenius/pricecoordinator/src/coordinator.ts
    - SuperGenius/pricecoordinator/test/tsconfig.json
    - SuperGenius/pricecoordinator/test/server.ts
    - SuperGenius/pricecoordinator/test/setup.ts
    - SuperGenius/pricecoordinator/test/hello.test.ts
  modified: []

key-decisions:
  - "Deviation: downgraded all npm pins to versions published ≥7 days before 2026-09-30 to satisfy the machine-wide npm `min-release-age=7` supply-chain policy (user-selected option). The STACK-researched pins (vitest-plugin 1.3.x, wrangler 4.144, msw 3.x, workers-types 5.20260929.1) were all published 2026-09-29 and were uninstallable under the policy."
  - "Added `\"type\": \"module\"` to package.json (not in KF-13 shape) — required for vitest 4 + the ESM-only plugin to load vitest.config.ts via rolldown-vite."
  - "Worker fetch stub uses the full (request, env, ctx) signature + exported `Env` interface instead of the plan's zero-arg stub — the plan's unit-style test passes 3 args, and the Env interface is the typed seam 01-02+ extends."
  - "Downgraded plugin's cloudflare:test does not export `IncomingRequest`; used the Workers-global `Request` constructor instead (documented fallback direction)."
  - "MSW/outboundService layering RESOLVED empirically (research A2): MSW patches the worker's fetch global inside workerd and answers mocked requests before they can descend to outboundService; only unmocked requests reach the guard. Guard stays fully active — no canary-only downgrade needed."

patterns-established:
  - "Egress guard contract: any unmocked outbound fetch in any test returns 599 {error:{code:'egress_blocked'}} — the contract every later test file inherits for free via vitest.config.ts"
  - "Single shared MSW network instance (test/server.ts) reused by all test files; lifecycle in test/setup.ts (extendable in 01-05 with reset()/abortAllDurableObjects)"
  - "Atomic per-task commits with {type}(01-01): scope inside the SuperGenius submodule on branch dev_tokenprice"

requirements-completed: [TEST-01, SRVC-03, SRVC-07]

duration: 42min
completed: 2026-09-30
---

# Plan 01-01: Project Scaffold Summary

**Greenfield Cloudflare Worker project at `SuperGenius/pricecoordinator/` with the full vitest-in-workerd harness proven green — `npm ci && npm run typecheck && npm run test` all exit 0, zero network egress proven by canary.**

## Performance

- **Duration:** ~42 min
- **Started:** 2026-09-30T17:20Z
- **Completed:** 2026-09-30T18:05Z
- **Tasks:** 2/2
- **Files created:** 12 (9 scaffold + 3 test)

## Accomplishments

- Toolchain de-risked end-to-end on the first plan, exactly as the roadmap intended: workerd runtime, wrangler config parsing, DO class wiring, both test invocation styles, MSW mocking, and the fail-closed egress guard all proven before any domain code exists.
- **MSW-vs-outboundService layering settled empirically** (KF-13 open question / assumption A2): mocked requests are answered by MSW inside the isolate; unmocked requests fall through to the `outboundService` guard and get `599 egress_blocked`. The guard remains the unconditional backstop for the whole suite.
- All 8 acceptance criteria for both tasks verified PASS (battery re-run after final file edits).

## Task Commits

1. **Task 1: Project scaffold — configs, pinned toolchain, DO stub** — `9c358daf2` (feat)
2. **Task 2: MSW test lifecycle + hello-world tests + hermeticity canary** — `351d7127c` (test)

Both in the `SuperGenius` submodule on branch `dev_tokenprice`.

## Files Created/Modified

- `package.json` — scripts (dev/test/typecheck), `"type": "module"`, policy-compatible pins
- `package-lock.json` — committed; `npm ci` green
- `wrangler.jsonc` — DO binding + `new_sqlite_classes` migration; no Queues/KV/secrets
- `tsconfig.json` / `test/tsconfig.json` — dual typecheck projects
- `vitest.config.ts` — cloudflareTest plugin + outboundService egress guard
- `.gitignore` — scoped: `node_modules/`, `.wrangler/`, `.dev.vars*`, `*.log`
- `src/index.ts` — stub fetch handler (full signature) + `Env` interface + DO re-export
- `src/coordinator.ts` — `PriceCoordinator extends DurableObject` stub
- `test/server.ts` / `test/setup.ts` / `test/hello.test.ts` — MSW instance, lifecycle, 4 harness proofs

## Observed Layering (KF-13 question — resolved)

```
test fetch(...) inside workerd
  └─ MSW-patched worker fetch global
       ├─ handler registered → answered by MSW (never leaves isolate)   [test 3: 200 mocked JSON]
       └─ no handler → falls through to miniflare outboundService
                        └─ guard returns 599 {error:{code:"egress_blocked"}}  [test 4: canary]
```

## Exact Installed Versions (lockfile)

| Package | Planned pin | Installed | Note |
|---|---|---|---|
| @cloudflare/vitest-plugin | ^1.3.3 | **1.2.4** | deviation — see below |
| @cloudflare/workers-types | ^5.20260929.1 | **5.20260923.1** | deviation |
| @msw/cloudflare | ^0.2.0 | **0.0.1** | deviation |
| msw | ^3.0.0 | **2.15.0** | deviation |
| typescript | ~5.9.0 | 5.9.3 | as planned |
| vitest | ^4.1.0 | 4.1.11 | as planned (4.x held) |
| wrangler | ^4.144.0 | **4.137.0** | deviation |

## Deviations from Plan

### User-Approved Decisions

**1. [User decision — environment policy] npm pins downgraded to satisfy `min-release-age=7`**
- **Found during:** Task 1 (npm install)
- **Issue:** Every STACK-researched pin was published 2026-09-29 — inside the machine-wide 7-day supply-chain delay (`~/.npmrc: min-release-age=7`) — so `npm install` failed with `ETARGET`. The plugin's whole 1.3.x line, wrangler 4.138–4.144, workers-types 5.2026092[3-9].1, msw 3.0.0, and @msw/cloudflare 0.1.0/0.2.0 are all affected.
- **Fix (user-selected "Downgrade pins"):** Newest mutually-compatible pre-cutoff set: plugin ^1.2.3 (peerDeps vitest ^4.1.0, deps wrangler 4.136.3 exact), wrangler ^4.136.3, msw ^2.15.0 (satisfies @msw/cloudflare@0.0.1 peer `>=2.14.1`), @msw/cloudflare ^0.0.1, workers-types ^5.20260922.1. vitest ^4.1.0 and typescript ~5.9.0 unchanged — both critical rules (4.x, not 7.x) held.
- **Files modified:** `package.json`
- **Verification:** `npm install` green; full suite green; versions recorded above.
- **Impact:** Low. The vitest-4/workers-types-5/TS-5.9 architecture is identical across these patch lines. The plugin 1.2.x API surface differs slightly: no `IncomingRequest` export from `cloudflare:test` (used Workers-global `Request` instead — documented fallback direction). **Follow-up:** once the newer versions age past the window (~2026-10-06), a `npm update` + re-run of the suite can restore the researched pins if desired — tests are the safety net.

### Auto-fixed Issues

**2. [Rule 1 — missing critical] `"type": "module"` required in package.json**
- **Found during:** Task 2 (`npm run test`)
- **Issue:** vitest 4 (rolldown-vite) tried to `require()` the ESM-only plugin while loading `vitest.config.ts` — startup error.
- **Fix:** Added `"type": "module"` to package.json (standard for Cloudflare templates; the KF-13 shape omitted it).
- **Verification:** `npm run test` green after the one-line change.

**3. [Rule 1 — missing critical] Worker fetch stub signature**
- **Found during:** Task 1 (typecheck)
- **Issue:** Plan specified `fetch(): Response` (zero args), but the plan's own Task-2 unit-style test invokes `worker.fetch(request, env, ctx)` — 3 args. Also the empty-`Cloudflare.Env` augmentation made the `env` import from `cloudflare:test` unassignable to a typed `Env`.
- **Fix:** Stub uses the real Workers signature `(request, env: Env, ctx: ExecutionContext)`; test constructs the env via a typed cast instead of importing the deprecated `env` binding.
- **Files modified:** `src/index.ts`, `test/hello.test.ts`
- **Verification:** typecheck + tests green.

**4. [Rule 1 — config hygiene] wrangler.jsonc comment strings would trip the 01-05 config test**
- **Found during:** Task 1 acceptance battery
- **Issue:** My explanatory comments mentioned `queues`, `kv_namespaces`, and `COINGECKO_API_KEY` verbatim; plan 01-05's `config.test.ts` asserts the raw file text does NOT contain those strings.
- **Fix:** Reworded comments (semantic descriptions, no forbidden tokens).
- **Verification:** `Select-String` battery all PASS.

**Total deviations:** 1 user-approved (version policy) + 3 auto-fixed. **Impact:** none on the plan's must-haves — every truth in the frontmatter was re-verified after the final edits.

## Self-Check: PASSED

All acceptance criteria re-run post-final-edit:
- `npm ci` → 0; `npm run typecheck` → 0 (both projects); `npm run test` → 4/4 (3.0s)
- `new_sqlite_classes` present; bare `new_classes": [` absent; `queues`/`kv_namespaces`/`COINGECKO_API_KEY` absent from `wrangler.jsonc`
- No `CMakeLists.txt`; zero references to `pricecoordinator` in any CMake file in the repo
- `.gitignore` five lines verified; `git check-ignore` confirms `node_modules` covered
- `export.*PriceCoordinator` present in `src/index.ts`; lockfile committed
