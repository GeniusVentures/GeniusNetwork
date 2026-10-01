# Phase 3: Local Price Manager - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-10-01
**Phase:** 3-Local Price Manager
**Areas discussed:** Threading & API shape, Coalescing mechanics, Fallback chain granularity, Test seam & client interface

---

## Threading & API shape

### Caller-facing surface

| Option | Description | Selected |
|--------|-------------|----------|
| Blocking result | `GetQuotes(ids, currency)` blocks until the chain resolves; drop-in for Phase 4's `GetCoinprice` seam | ✓ |
| Async callback | `GetQuotesAsync(..., callback)`; forces Phase 4 restructure | |
| Both | Async core + blocking wrapper; two APIs to test | |

**User's choice:** Blocking result
**Notes:** Recommended — matches the synchronous `outcome::result` seam Phase 4 must preserve (LPM-10).

### Ownership model

| Option | Description | Selected |
|--------|-------------|----------|
| Injected member | Manager owns ioc + dedicated thread; constructed once, injected into GeniusNode in Phase 4 | |
| Singleton (ComponentFactory) | Register in CComponentFactory; couples pure manager to singleton registry | |
| Caller-supplied executor | Passive manager; Phase 4 solves threading | |
| (freeform) | "Just use the same pattern as coinprices.cpp, it looks like it just creates an ioc and then passes to filemanager" | ✓ |

**User's choice:** Free-text — coinprices.cpp pattern
**Notes:** Clarifying exchange followed: Claude reflected that the throwaway-ioc-per-call pattern cannot coalesce across threads (shared ioc run by multiple threads → run()/restart() tail-coupling, the Phase 2 gap #2 landmine). User then proposed: "when constructing a PriceHttpClient we could pass an ioc to it and have it use that, wouldn't that solve this?" Claude analyzed: construction-time ioc solves the executor question but still needs one thread calling `run()`; two completions offered (A: shared ioc + one runner thread; B: leader/waiter with throwaway iocs). User selected **A** — final decision D-02 supersedes the throwaway-ioc reading for the manager.

### Concurrency model

| Option | Description | Selected |
|--------|-------------|----------|
| Single in-flight | One fetch at a time; window serializes upstream traffic | ✓ |
| Concurrent tiers | Tier fan-out; faster failover, more states | |

**User's choice:** Single in-flight
**Notes:** Price traffic is low-volume; ~5s timeout bounds the tail.

---

## Coalescing mechanics

### Window collection

| Option | Description | Selected |
|--------|-------------|----------|
| Fixed 50ms delay | First miss arms steady_timer; union dispatch; all waiters block on futures | ✓ |
| Immediate + join-in-flight | Zero added latency; weaker union guarantee | |
| Hybrid append | Append until HTTP write; most states to test | |

**User's choice:** Fixed 50ms delay
**Notes:** Exactly the roadmap's "~50ms coalescing window" wording.

### Partial L1 hit behavior

| Option | Description | Selected |
|--------|-------------|----------|
| Fetch only misses | Fresh ids served from cache; misses enter window/batch | ✓ |
| All-or-nothing refetch | Whole set upstream on any miss | |

**User's choice:** Fetch only misses
**Notes:** Mirrors today's `GeniusNode::GetCoinprice` miss-collection loop.

### Requests arriving during in-flight fetch

| Option | Description | Selected |
|--------|-------------|----------|
| New window queues | New pending window dispatches after in-flight completes; no id fetched twice | ✓ |
| Wait then immediate | Block until landing, dispatch without second window | |

**User's choice:** New window queues
**Notes:** Deterministic; two bursts = at most two sequential batches.

---

## Fallback chain granularity

### Failure escalation

| Option | Description | Selected |
|--------|-------------|----------|
| Batch + gap-chase | Wholesale failure escalates whole miss-set; partial success chases per-id gaps at token.gnus.ai | ✓ |
| Strict batch-only | Gaps fall to LKG/error; WAF-blocked id poisons batches | |
| Per-id chain | Destroys LPM-03 batching | |

**User's choice:** Batch + gap-chase
**Notes:** Partial coverage follows Phase 1 D-09 (absent ids are not errors).

### Last-known-good store

| Option | Description | Selected |
|--------|-------------|----------|
| L1 = LKG (aged entries) | Stale-band L1 entries serve when network tiers fail; one cache, two modes | ✓ |
| Separate LKG map | Contradicts FRESH-02's >5min-unavailable band | |

**User's choice:** L1 = LKG (aged entries)
**Notes:** D-14 fetch timestamps + ClassifyFreshness already provide the machinery.

### LKG serving flags

| Option | Description | Selected |
|--------|-------------|----------|
| LocalCache + stale | source: LocalCache, stale: true, timestamp unchanged | ✓ |
| Original source + stale | Blurs which tier served; confusable with envelope source semantics | |

**User's choice:** LocalCache + stale
**Notes:** Consumer sees "cache value, old" — honest and simple.

---

## Test seam & client interface

### Injection boundary

| Option | Description | Selected |
|--------|-------------|----------|
| One IPriceSource | Single interface matching FetchPrices shape; two instances; fakes script results + call counts | ✓ |
| Stub URLs (no interface) | Real client + HttpStubServer; violates TEST-02's no-sockets letter | |
| Per-tier interfaces | Identical shapes; doubles fake surface | |

**User's choice:** One IPriceSource
**Notes:** Real client implements it with zero logic change.

### Phase 2 gap #3 fold-in

| Option | Description | Selected |
|--------|-------------|----------|
| Fold into Phase 3 | Carry transport-error classification in PriceFetchFailure; gate retries on IsTransientTransport | ✓ |
| Defer the fix | Manager works around coarse classification | |

**User's choice:** Fold into Phase 3
**Notes:** Directly serves TEST-02's retry-classification assertion.

### Manager class name

| Option | Description | Selected |
|--------|-------------|----------|
| LocalPriceManager | Matches roadmap phase name; device-side distinction vs. server-side PriceCoordinator | ✓ |
| PriceManager | Shorter; loses the distinction | |

**User's choice:** "LocalPriceManager is fine" + free-text question
**Notes:** User asked whether Phase 1's coverage "does in fact run the node based pricecoordinator and get prices from that with a socket." Claude clarified: Phase 1 runs the real worker+DO in workerd with mocked upstream (zero sockets); Phase 2 uses real loopback sockets; Phase 3 is pure fakes — exposing a cross-tier contract gap. Offered: (1) Phase 3 fixtures replay real Phase 1 envelope JSON (in scope), (2) live wrangler-dev end-to-end test (deferred). User answered **Yes** to that split → D-16 + deferred idea.

---

## Claude's Discretion

- `IPriceSource` header name/location; pure virtual class vs. function injection
- L1 cache keying (per-id vs. per-(id,currency)); per-currency pending-window structure
- 50ms constant's config surface (must be injectable for deterministic tests)
- Gap #3 classification shape (new field vs. variant) — behavior fixed, shape free
- Chain-walk logging detail
- How much of legacy `coinprices.cpp` retriever is deleted vs. left compiling (Phase 4 owns cutover)

## Deferred Ideas

- Live end-to-end test: real `wrangler dev` worker + C++ manager over loopback (future phase)
- Second hold-off timer for token.gnus.ai tier (only if abuse observed)
- Async `GetQuotes` variant (when a real consumer exists)
- Carried from Phase 1: aarch64-Debug exclusion removal needs MNN/Vulkan rebuild rider (Phase 5 re-scope)
