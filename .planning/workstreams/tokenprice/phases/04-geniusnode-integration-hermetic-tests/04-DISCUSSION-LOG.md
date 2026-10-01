# Phase 4: GeniusNode Integration & Hermetic Tests - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-10-01
**Phase:** 4-GeniusNode Integration & Hermetic Tests
**Areas discussed:** Endpoint config surface, Seam cutover mechanics, Retriever retirement scope, Hermetic test shapes

---

## Endpoint config surface (LPM-09)

### Q1: How should price endpoint base URLs be configured?

| Option | Description | Selected |
|--------|-------------|----------|
| Env vars only | SGNS_COINGECKO_URL / SGNS_PRICE_FALLBACK_URL read at manager construction; tests set env before GeniusNode::New. Precedent: SGNS_CONSOLE_LOG_TESTS, SGNS_DEBUGLOGS | ✓ |
| GeniusNodeConfig only | New trailing aggregate fields sourced from sgns_config.json | |
| Both, env wins | Config fields with env override precedence | |
| You decide | Weigh CI-matrix operability vs plumbing cost | |

**User's choice:** Env vars only
**Notes:** GeniusNodeConfig stays untouched — brace-initialized aggregate; appending fields would touch every construction site for no benefit.

### Q2: Env-var shape for the two tiers?

| Option | Description | Selected |
|--------|-------------|----------|
| Tier-specific names | One var per tier; tests redirect each tier independently | ✓ |
| One URL for both | Single SGNS_PRICE_BASE_URL for both tiers | |
| You decide | Only constraint: hermetic test can redirect CoinGecko tier while fallback is default or scripted separately | |

**User's choice:** Tier-specific names

### Q3: How do hermetic tests redirect a constructed GeniusNode?

| Option | Description | Selected |
|--------|-------------|----------|
| Env set before New() | Test sets env before GeniusNode::New, restores in teardown; no new node API | ✓ |
| Env + setter method | Env at construction plus a post-construction setter | |
| You decide | Solve the fixture constraint (node_ built in fixture ctor) keeping the test honest | |

**User's choice:** Env set before New()
**Notes:** The AccountManagement fixture sets env in its ctor before New — redirecting every node the suite constructs, making the whole suite hermetic.

### Q4: TLS verification when redirected to a local stub?

| Option | Description | Selected |
|--------|-------------|----------|
| Scheme in URL decides | http:// stub URL = plain HTTP; https:// production defaults keep TLS + pinned CA | ✓ |
| TLS even to stub | Would need self-signed test certs — heavier, zero production benefit | |

**User's choice:** Scheme in URL decides

---

## Seam cutover mechanics (LPM-10)

### Q1: Where does the LocalPriceManager live in GeniusNode?

| Option | Description | Selected |
|--------|-------------|----------|
| Lazy shared_ptr member | Constructed on first price call; no thread until needed; manager destructor joins runner | ✓ |
| Eager construction | Built in GeniusNode ctor; thread for whole lifetime | |
| Per-call manager | Fresh manager per GetCoinprice — defeats L1/coalescing entirely | |

**User's choice:** Lazy shared_ptr member

### Q2: Fate of GeniusNode's own price cache state?

| Option | Description | Selected |
|--------|-------------|----------|
| Delete outright | m_tokenPriceCache, m_lastApiCall, MIN_API_CALL_INTERVAL, PriceInfo, miss-loop all removed | ✓ |
| Keep, unused | Smaller diff but dead misleading state | |

**User's choice:** Delete outright

### Q3: Partial-success mapping on the outcome::result<map> surface?

| Option | Description | Selected |
|--------|-------------|----------|
| Partial map + err on empty | Servable ids in the map; unservable absent; error only when nothing servable (today's behavior + Phase 3 semantics) | ✓ |
| All-or-nothing | Any failed id fails the call — stricter than today | |

**User's choice:** Partial map + err on empty
**Notes:** GetGNUSPrice's finite/positive validation stays untouched and yields NO_PRICE when genius-ai is absent.

---

## Retriever retirement scope

### Q1: How far does CoinGeckoPriceRetriever retirement go?

| Option | Description | Selected |
|--------|-------------|----------|
| Delete whole class | All endpoints, helpers, forwarders (GetCoinPriceByDate/Range) — verified zero external consumers | ✓ |
| Current-only deletion | Keep historical methods compiling (REQUIREMENTS Out-of-Scope wording) | |
| Keep whole class | Stop calling it; leaves WAF-buggy client code in-tree | |

**User's choice:** Delete whole class
**Notes:** User's decision overrides REQUIREMENTS.md's Out-of-Scope "historical endpoints kept compiling" entry — recorded as a Requirements Correction in CONTEXT.md. During discussion, greps confirmed no consumers in SuperGenius/src/api, gRPCForSuperGenius, SGProcessingManager, GeniusSDK, or other tests.

---

## Hermetic test shapes (TEST-04/TEST-05)

### Q1: What does price_retrieval_test become?

| Option | Description | Selected |
|--------|-------------|----------|
| Rewrite as integration | Drives real wired path (GeniusNode::GetCoinprice) against HttpStubServer with env redirection; registered with CTest; historical tests deleted with the retriever | ✓ |
| Delete the suite | facade/manager tests exist but nothing proves the wiring end-to-end | |
| Keep tests, stub them | Impossible — retriever deleted; historical still live-network | |

**User's choice:** Rewrite as integration

### Q2: Stub topology for the redirected node tests?

| Option | Description | Selected |
|--------|-------------|----------|
| One stub, both tiers | Same HttpStubServer, different scripted paths (/api/v3/simple/price vs /v1/prices) | ✓ |
| CoinGecko tier only | Fallback stays on real token.gnus.ai — undeployed (DEPLOY-01), would just fail | |
| Two stub instances | More isolation, zero added coverage | |

**User's choice:** One stub, both tiers

### Q3: How does account_management_test.SetPayoutAddress get stubbed?

| Option | Description | Selected |
|--------|-------------|----------|
| Env in fixture ctor | Env vars set in AccountManagement ctor before any GeniusNode::New; both tiers → shared stub with valid genius-ai price; topology/escrow/assertions untouched | ✓ |
| Per-test env only | node_ built in fixture ctor — other tests' nodes would stay live-network | |
| Other approach | — | |

**User's choice:** Env in fixture ctor

### Q4: Does the integration suite prove fallback/LKG through the node seam?

| Option | Description | Selected |
|--------|-------------|----------|
| Warm-then-fail script | First calls succeed (populate L1/LKG), then flip stub to 403/429 — fallback tier or stale LKG keeps serving | ✓ |
| Happy path only | Fallback/LKG proven only in manager fakes | |

**User's choice:** Warm-then-fail script
**Notes:** This proves the milestone's Core Value (price paths never hard-fail under WAF/rate-limit) end-to-end.

---

## Claude's Discretion

- Exact env-var name strings (tier-specific SGNS_* shape locked by D-02)
- Env-read implementation location (free function vs inline at lazy-ctor site); unset-env fallback constants
- Lazy construction shape (GetOrCreatePriceManager helper vs inline)
- Manager release placement within ~GeniusNode's ordered teardown
- coinprices.hpp/.cpp file disposition after deletion (module keeps Phase 2/3 files)
- Rewritten suite's TEST_F organization and addtest registration mechanics
- Fixture env save/restore helpers (RAII vs gtest Environment) — must not leak into other suites in the shard
- Assertion style for fallback/LKG scenarios (value equality vs presence + sanity)

## Deferred Ideas

- CI workflow changes (worker-tests job, aarch64-Debug exclusion removal + MNN/Vulkan rider): Phase 5
- Live end-to-end test (wrangler dev worker + C++ manager over loopback): future milestone (carried from Phase 3)
- Config-file operability for price endpoints (sgns_config.json / GeniusNodeConfig): rejected for v1, revisit on operator demand
- Second hold-off timer for token.gnus.ai tier: carried unchanged from Phase 3
