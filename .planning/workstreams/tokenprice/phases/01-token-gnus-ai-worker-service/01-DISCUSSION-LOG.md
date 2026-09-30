# Phase 1: token.gnus.ai Worker Service - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-09-29
**Phase:** 1-token.gnus.ai Worker Service
**Areas discussed:** Repo placement, CoinGecko key handling, Envelope & error contract, DO storage semantics

---

## Repo placement

| Option | Description | Selected |
|--------|-------------|----------|
| SuperGenius/tokenpriceservice/ | Sibling of src/ like evmrelay/, gRPCForSuperGenius/, GeniusKDF/. Required for Phase 5's path filter; invisible to CMake; research-recommended. | ✓ (placement) |
| GeniusNetwork top-level | Lives in root repo outside any submodule. But SuperGenius's cmake.yml can't path-trigger on it — Phase 5 would need a different workflow location or drop the path filter. | |
| Separate new repo | Its own repo (e.g. GeniusVentures/token-price-coordinator). Cleanest isolation but contradicts plan 05-01 as written and adds repo-provisioning work. | |

| Option | Description | Selected |
|--------|-------------|----------|
| tokenpriceservice | Matches STACK.md/ARCHITECTURE.md research and the service domain name. | |
| pricecoordinator | Named after the DO class / design doc concept. | ✓ |
| priceworker | Emphasizes Cloudflare Worker. Clear but generic. | |

**User's choice:** SuperGenius submodule placement + `pricecoordinator` directory name
**Notes:** Placement rationale locked on the CI constraint: GitHub workflows only see paths inside their own repository, so the Phase 5 `worker-tests` path filter in SuperGenius's cmake.yml requires the directory to live in the SuperGenius submodule. The name overrides the research docs' `tokenpriceservice`.

---

## CoinGecko key handling

| Option | Description | Selected |
|--------|-------------|----------|
| Optional secret now | Worker reads env.COINGECKO_API_KEY (wrangler secret, optional); adds x-cg-demo-api-key header when set; anonymous when unset; both paths tested. | ✓ |
| Anonymous-only | No key plumbing this milestone — a later code change + redeploy needed when keyed access lands. | |
| Keyless default + flip | Wire the secret AND default to keyless with a documented flip (effectively same as option 1). | |

| Option | Description | Selected |
|--------|-------------|----------|
| Global, not per-currency | Key applied identically to all upstream calls regardless of currency DO instance; currency is not a key axis. | ✓ |
| Per-currency keys | Different keys per currency instance — no requirement support; complexity without benefit. | |

**User's choice:** Optional secret now, global scope
**Notes:** Deployment later just sets the secret — zero code change at DEPLOY time.

---

## Envelope & error contract

| Option | Description | Selected |
|--------|-------------|----------|
| coingecko / coingecko-cache | Exactly the two strings in the design reference's JSON examples; C++ maps to PriceSource::CoinGecko / GnusPriceService. | ✓ |
| Three values (colo/DO split) | Adds "cloudflare-cache" for caches.default-served responses. More observability, three values to keep in sync. | |

| Option | Description | Selected |
|--------|-------------|----------|
| Stale-first, 502 if none | Serve DO cache stale-flagged when upstream fails; structured 502 only when nothing usable exists. | ✓ |
| Always 502 on upstream fail | Surfaces upstream failure even when stale cache exists. Contradicts SRVC-05/FRESH-02. | |
| Always 200 + error field | Non-standard; hides failures from HTTP monitoring; C++ must parse body to detect failure. | |

| Option | Description | Selected |
|--------|-------------|----------|
| 502 + JSON error body | {error:{code,message,upstreamStatus?}}; 400 malformed ids/vs; 404 unknown paths; 405 non-GET. upstreamStatus included when CoinGecko returned an HTTP status. | ✓ |
| Pass upstream status through | Lets CoinGecko's limiter dictate our response codes; C++ can't distinguish 'service broken' from 'you are limited'. | |
| 503 generic | Loses diagnostic detail; harder to distinguish scenarios in tests. | |

| Option | Description | Selected |
|--------|-------------|----------|
| Omit missing ids silently | prices object includes only returned ids; clients derive absence by diffing. | ✓ |
| Explicit missing field | Adds "missing":[ids] array; extends beyond locked SRVC-01 envelope shape. | |

**User's choice:** All recommended options — two-value source, stale-first/502-if-none, 502+JSON error body, omit missing ids silently
**Notes:** This contract is what Phase 2/3 C++ code parses — exactness is the point.

---

## DO storage semantics

| Option | Description | Selected |
|--------|-------------|----------|
| Row per id | id TEXT PRIMARY KEY, price REAL, fetchedAt INTEGER; partial batch responses never clobber older rows. | ✓ |
| Row per batch | Fewer rows but JSON parsing on reads; per-id freshness impossible under partial batches. | |
| Hybrid Map + SQL | In-memory Map + write-through SQL; dual-source-of-truth complexity. | |

| Option | Description | Selected |
|--------|-------------|----------|
| Per-id timestamps | Envelope fetchedAt = max(fetchedAt of returned ids); age = now − max; stale:true when ANY id >60s. | ✓ |
| Per-batch timestamp | All ids in a batch share one fetchedAt; misreports ages under partial responses. | |

| Option | Description | Selected |
|--------|-------------|----------|
| 60s fresh / 5min cutoff | Serve from SQL when every requested id ≤60s; refetch only older ids; 60s–5min served stale-flagged only on upstream failure; >5min never served. | ✓ |
| Indefinite last-known-good | Keeps rows indefinitely for error serving even >5min. Maximizes availability but >5min prices are wrong for cost estimation. | |

**User's choice:** Row per id, per-id timestamps, 60s/5min band gates (FRESH-01 exact)
**Notes:** None.

---

## User Correction (recorded mid-discussion)

The user corrected a wrong premise inherited from the diagnosis memory: `AccountManagement.SetPayoutAddress` is excluded on Linux aarch64-Debug CI **because of the MNN VulkanInstance assert** (no usable Vulkan device on the ARM runner's lavapipe ICD; Debug-only since NDEBUG compiles the assert out) — **not** because of CoinGecko. Hermetic prices alone will not make that exclusion removable; removal needs the thirdparty MNN rebuild. Phase 5 plan 05-02 / TEST-04 clause 2 need re-scoping (captured in CONTEXT.md `<deferred>`; memory file `/memories/repo/coingecko-price-api-frontend.md` corrected 2026-09-29). Phase 4's hermetic conversion of the test itself remains valid — the test is genuinely network-dependent on live CoinGecko today.

## Claude's Discretion

- npm script names beyond dev/test/typecheck; vitest test-file organization; `wrangler.jsonc` `compatibility_date`; error `code` string tokens; internal module split; single-flight promise-sharing implementation details; SQL row pruning policy (delete >5min rows vs keep-but-unservable).

## Deferred Ideas

None — discussion stayed within phase scope. The Phase 5/TEST-04 re-scoping note is a correction to an existing roadmap item, not a new capability.
