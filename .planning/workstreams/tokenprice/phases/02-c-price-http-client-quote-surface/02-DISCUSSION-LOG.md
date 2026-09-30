# Phase 2: C++ Price HTTP Client & Quote Surface - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-09-30
**Phase:** 2-C++ Price HTTP Client & Quote Surface
**Areas discussed:** Client scope & shape, TLS & connection policy, Retry & backoff rules, Quote types & error model

---

## Client scope & shape

**Q1: Why Boost.Beast explicitly in SuperGenius when AsyncIOManager exists for HTTP retrieval?**

Presented as a scope question (current-prices-only vs generic GET client vs all three endpoints) but the user challenged the premise:

> "Why would we use boost beast explicitly in supergenius, we have asynciomanager for http retrieval, which is at least boost based? ... If we need to update anything for status, TLS, timeouts, we should update asynciomanager."

Claude re-verified `thirdparty/AsyncIOManager/src/HTTPCommon.cpp` live and confirmed the research's gap list (status stripped at `\r\n\r\n` slice; `s_verify_peer` is a latent no-op — nothing calls verify_peer or loads CAs; UA hard-coded; timeouts fixed 10/10/30s; unconditional `ssl::stream` blocks plain HTTP). The challenge was upheld.

| Option | Description | Selected |
|--------|-------------|----------|
| Upgrade AsyncIOManager | New status-aware surface on HTTPDevice; TLS verify fix; plain-HTTP; configurable timeouts/UA; thirdparty submodule cycle | ✓ |
| Beast in SuperGenius | Price-scoped Beast client per original plan; contained but leaves HTTPDevice verification latent | |
| Split: fix TLS only | Tiny TLS rider in thirdparty + scoped Beast client for prices | |

**User's choice:** Upgrade AsyncIOManager
**Notes:** Original plan text (roadmap seeds 02-02/02-03, LPM-06 wording) superseded; intent unchanged, vehicle changed. Recorded as D-01.

---

**Q2: Historical-endpoint URL shapes (path+query, chunked) — gap or not?**

| Option | Description | Selected |
|--------|-------------|----------|
| Defer historical-endpoint compat | No transport rework until Phase 4 decides their fate | |
| Full URL + chunked now | Surface handles query strings + chunked decoding immediately | |

**User's choice:** (free text) No real gap exists
**Notes:** User: "I'm pretty sure we already send a path+query url? We're basically sending the same thing to localhost? Not seeing a problem really other than our local tests not being https, and we can have asynciomanager support non-https. Just remember that asynciomanager is a kind of singleton design that handles many types of URLs ... through virtual classes." Verified: `parseHTTPUrl` keeps query in path; `RegisterLoader("http", ...)` is commented out at `HTTPLoader.cpp:34` — the actual work item. Recorded as D-03/D-04.

---

**Q3: Submodule mechanics scheduling**

| Option | Description | Selected |
|--------|-------------|----------|
| Rider commit flow | AsyncIOManager work inside Phase 2, innermost-first commits | ✓* |
| Separate pre-phase | Standalone mini-phase before 02-01 | |

**User's choice:** (free text) Included with Phase 2
**Notes:** "It can be included with phase 2, just make sure to make a dev_tokenprice on asynciomanager/thirdparty." Recorded as D-05. No push without explicit approval (standing rule).

---

**Q4: TLS verification fix blast radius**

| Option | Description | Selected |
|--------|-------------|----------|
| New surface only | verify_peer+CA+hostname on the status-aware surface; LoadASync consumers unchanged | ✓ |
| Fix for all consumers | Every LoadASync consumer starts verifying certs | |

**User's choice:** New surface only
**Notes:** Zero blast radius beyond the new API; avoids breaking odd-cert endpoints in the 16-config matrix. Recorded as D-06.

---

## TLS & connection policy

**Q1: CA bundle source**

| Option | Description | Selected |
|--------|-------------|----------|
| In-repo cacert.pem | CA file at configurable path, default in-repo bundle shipped with SuperGenius | ✓ |
| System trust store | OpenSSL default verify paths; varies by CI container | |
| System then bundle | Fallback chain; most robust, more code | |

**User's choice:** In-repo cacert.pem
**Notes:** Recorded as D-07.

---

**Q2: User-Agent policy**

| Option | Description | Selected |
|--------|-------------|----------|
| Configurable per call | Per-request/per-device UA; price client sends CoinGecko-friendly string | ✓ |
| Improved global default | One better-crafted UA for all HTTPDevice traffic | |

**User's choice:** Configurable per call
**Notes:** Recorded as D-08.

---

**Q3: io_context / threading model**

| Option | Description | Selected |
|--------|-------------|----------|
| Caller-supplied ioc | HTTPDevice stays executor-agnostic; Phase 3 manager owns io_context+thread | ✓* |
| Owned thread pool | AsyncIOManager grows its own IO pool | |

**User's choice:** (free text) Status quo
**Notes:** "Continue as we have been doing, I think we provide an ioc?" Recorded as D-09.

---

**Q4: Timeout configuration**

| Option | Description | Selected |
|--------|-------------|----------|
| Per-request, 5s default | Price client sets ≈5s per LPM-06; LoadASync keeps 10/10/30s | ✓ |
| Keep 10/10/30s | Fixed unconditionally; fails LPM-06 criterion | |

**User's choice:** Per-request, 5s default
**Notes:** Recorded as D-10.

---

## Retry & backoff rules

**Q1: Retryable failure set**

| Option | Description | Selected |
|--------|-------------|----------|
| Transport errors only | Timeout/reset/DNS; never 403/429/4xx/5xx/malformed | ✓ |
| Add single 5xx retry | One retry on 5xx after backoff; roadmap says 5xx falls through | |

**User's choice:** Transport errors only
**Notes:** Recorded as D-11.

---

**Q2: Backoff schedule shape**

| Option | Description | Selected |
|--------|-------------|----------|
| Fixed 1/2/4s, cap 3 | Deterministic, easy to assert; constants configurable | ✓ |
| Exponential + jitter | More correct distributed-client behavior; harder to test | |
| Configurable, 0ms in tests | Determinism via injection rather than shape | |

**User's choice:** Fixed 1/2/4s, cap 3
**Notes:** Recorded as D-12.

---

**Q3: 429 no-sub-minute-retry enforcement**

| Option | Description | Selected |
|--------|-------------|----------|
| Client-side hold-off timer | Hold-until timestamp skips CoinGecko tier; injectable clock | ✓ |
| No explicit tracking | Rely on L1 freshness only; weaker guarantee | |

**User's choice:** Client-side hold-off timer
**Notes:** Recorded as D-13.

---

## Quote types & error model

**Q1: PriceQuote::timestamp semantics**

| Option | Description | Selected |
|--------|-------------|----------|
| Fetch time (fetchedAt) | Aligned with envelope fetchedAt / DO per-id rows (Phase 1 D-11) | ✓ |
| Local store time | Diverges from envelope age math; needs re-basing | |

**User's choice:** Fetch time (fetchedAt)
**Notes:** Recorded as D-14.

---

**Q2: Error taxonomy shape**

| Option | Description | Selected |
|--------|-------------|----------|
| Typed enum + status | outcome::result with price-specific enum carrying HTTP status (extends PriceError pattern) | ✓ |
| error_code category | boost::system category; heavier machinery | |

**User's choice:** Typed enum + status
**Notes:** Recorded as D-15.

---

**Q3: Freshness band boundaries**

| Option | Description | Selected |
|--------|-------------|----------|
| Closed fresh boundaries | ≤60s Fresh; 60s<age≤5min StaleButUsable; >5min Unavailable | ✓ |
| Open fresh boundaries | Exactly 60s counts stale; off-by-one at tier seams | |

**User's choice:** Closed fresh boundaries
**Notes:** Recorded as D-16; matches Worker D-12 gates exactly.

---

## Claude's Discretion

- New-surface API shape on HTTPDevice (method names, request/response structs), file layout in AsyncIOManager, plain-HTTP loader class design
- PriceQuote/PriceSource header location and exact timestamp representation
- Stub server implementation details (Beast acceptable for the test fixture; OS-assigned port; per-path scripting) provided it drives the upgraded surface
- cacert.pem sourcing and in-repo location
- Retry-state placement (per-device vs price-client-owned) with injectable clock

## Deferred Ideas

None new. Carried forward from Phase 1: aarch64-Debug exclusion removal needs the MNN/Vulkan thirdparty rider — re-scope Phase 5's 05-02/TEST-04 clause when planning that phase. CONTEXT.md also records the roadmap-wording corrections D-01 requires the planner to apply.
