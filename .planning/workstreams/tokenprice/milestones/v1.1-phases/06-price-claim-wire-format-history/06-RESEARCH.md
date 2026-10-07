# Phase 6: Price Claim Wire Format & History - Research

**Researched:** 2026-10-05
**Domain:** C++ (SuperGenius) — protobuf wire field, quote plumbing, strand-confined price history
**Confidence:** HIGH for code anchors (read this session); MEDIUM for test-harness details

<user_constraints>
## User Constraints (from 06-CONTEXT.md)

### Locked Decisions
- **D-06-01 Quote plumbing:** `GetProcessCost` returns a struct `{minions, PriceQuote}` so `ProcessImage` stamps price from the same quote that sized the escrow (single read, WIRE-02). `GetGNUSPrice`/`GetCoinprice` keep their `double` API as thin wrappers; no SDK/wallet-facing break.
- **D-06-02 Wire fields:** `SGProcessing::Task` gains ONLY a claimed price (`double`, USD per genius-ai, new field number 6). No separate timestamp field: escrow tx carries `EscrowTx.amount` and `DAGStruct.timestamp`, reachable via `task.escrow_path`. Supersedes "price_timestamp" wording in REQUIREMENTS.md D-01/WIRE-01 and ROADMAP criterion 2.
- **D-06-03** Validator reference time = escrow DAG timestamp; window looks back quote TTL + clock skew (Phase 7).
- **D-06-04** Cost binding: `CalculateCostMinions(blockSize, claimed_price) == escrow amount` (Phase 7).
- **D-06-05 History:** `LocalPriceManager` records every `genius-ai` quote actually fetched from a network tier (CoinGecko / GnusPriceService); NOT L1 cache hits. Bounded ring buffer, configurable retention (default ~24h, plus count cap). Queries: min/max/count over a time window.
- **D-06-06 Restart:** in-memory only; empty after restart (HIST-02 = documented safe degradation).
- **D-06-07** History is local evidence only, not a validity ruling.

### Agent's Discretion
Struct/field names, ring buffer data structure, locking model (follow manager's strand), config key names.

### Deferred Ideas (OUT OF SCOPE)
Trust/reputation for posters; Phase 7 tolerance/window defaults, legacy-task policy; Phase 8 consensus hook.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| WIRE-01 | Task carries claimed price | Add `double claimed_price = 6;` to `SGProcessing::Task` (proto, fields 1-5 used) |
| WIRE-02 | Price stamped is the one used to size escrow | `GetProcessCost` returns `{minions, quote}`; ProcessImage uses `quote.price` |
| HIST-01 | Bounded local history of observed prices, window queries | Ring buffer in `LocalPriceManager`, recorded in tier-success path |
| HIST-02 | Empty-after-restart safe degradation | In-memory; query returns count=0; document |
</phase_requirements>

## Summary

The change is small and localised: one proto field, one struct return type in `GeniusNode`, one stamp line in `ProcessImage`, and a strand-confined history in `LocalPriceManager`. The only real design risk is the *single read* guarantee: today `GetProcessCost` calls `GetGNUSPrice()` → `GetCoinprice()` → `GetQuotes()` which discards the `PriceQuote` and returns only `double`. The plumbing must keep the quote (with its `price`) from that same call; a second `GetGNUSPrice()` call in `ProcessImage` would be racy (price can change between reads, or cache can expire) and violates WIRE-02.

History must record in the network-fetch path only (`DispatchBatchOnStrand`), not in `HandleRequestOnStrand` L1-hit path. Queries must go through the strand (post + future), like `GetQuotes`, since all state is strand-confined with no mutexes.

**Primary recommendation:** Add `double claimed_price = 6;`; introduce `struct ProcessCost { uint64_t minions; PriceQuote quote; }` (or `outcome::result<>`), refactor `GetProcessCost` to call `GetOrCreatePriceManager()->GetQuotes({"genius-ai"},"usd")` directly via a shared private helper `GetGNUSQuote()` that `GetGNUSPrice` also wraps; add `PriceHistory` (deque ring) to `LocalPriceManager` appended on tier success, with a blocking `QueryHistory(asset, currency, from, to)` returning `{count,min,max}`.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary | Rationale |
|------------|-------------|-----------|-----------|
| Claimed price stamping | API/Backend (GeniusNode::ProcessImage) | — | Poster node builds Task |
| Wire format | Shared proto (SGProcessing.proto) | — | Replicated over CRDT/pubsub |
| Price history | Node-local (LocalPriceManager strand) | — | In-memory, per-node evidence (D-04 independence) |

## Standard Stack

No new packages. Existing: protobuf (generated from SGProcessing.proto), Boost.Asio strand, Boost.Outcome, GoogleTest. **Package Legitimacy Audit:** no external packages installed — N/A.

## Architecture Patterns

### Data flow
```
ProcessImage -> GetProcessCost(procmgr) -> GetGNUSQuote() -> LocalPriceManager::GetQuotes (strand)
     |                                             |-- L1 hit: serve cached quote (NOT recorded)
     |                                             '-- miss: DispatchBatchOnStrand -> tier walk -> [RECORD history] -> StoreInL1
     |<- {minions, quote}
     '-> task.set_claimed_price(quote.price)   (same quote that sized funds/escrow)
```

### Code anchors (read this session, SuperGenius/)
- `src/account/GeniusNode.cpp:2680-2692` `ProcessImage`: `auto funds = GetProcessCost( *procmgr ); if ( funds <= 0 )` — returns `uint64_t`; error is signalled by 0. Task built at `:2701-2710` (`task.set_ipfs_block_id/json_data/random_seed/results_channel`); escrow_path set later (grep `set_escrow_path` — not re-verified). Stamp `task.set_claimed_price(...)` next to `:2709`.
- `:2806-2835` `GetProcessCost`: calls `GetGNUSPrice()` at `:2816`, then `TokenAmount::CalculateCostMinions( blockLen.value(), gnusPrice )` at `:2825`.
- `:2837-2852` `GetGNUSPrice`: `GetCoinprice( { "genius-ai" } )`, validates `std::isfinite && > 0`, else `Error::NO_PRICE`. **Keep this validation** in the new helper.
- `:3550-3573` `GetCoinprice`: `GetOrCreatePriceManager()->GetQuotes( tokenIds, "usd" )` then flattens to `map<string,double>` (loses quote).
- `src/account/GeniusNode.hpp:382` `uint64_t GetProcessCost(...)`, `:406` `GetGNUSPrice()`, `:838` `GetCoinprice`, `:1476` `priceManager_`, `:1482` `GetOrCreatePriceManager()`; `GeniusNode.cpp:3519-3545` creates `LocalPriceManager( tier1, tier2 )`.
- `src/account/TokenAmount.hpp:115` `static outcome::result<uint64_t> CalculateCostMinions( uint64_t total_bytes, double price_usd_per_genius );`
- `src/coinprices/PriceQuote.hpp`: `struct PriceQuote { asset, currency, double price, system_clock::time_point timestamp /*FETCH time D-14*/, PriceSource source, bool stale; FetchedAtEpochSeconds() }`. `PriceSource { LocalCache, CoinGecko, GnusPriceService, OnChain }`.
- `src/coinprices/LocalPriceManager.hpp`: ctor `(coinGeckoTier, gnusServiceTier, coalescingWindow=50ms, Clock now)` at `:53-56`; `GetQuotes` `:82`; private `HandleRequestOnStrand :108`, `DispatchBatchOnStrand :115`, `StoreInL1 :120`; members `ioc_ :126`, `strand_ :128`, `now_ :132`, `cache_ :136`, `windows_ :140`, `thread_ :143` (declaration order load-bearing — add history member AFTER `windows_`, before `m_logger`/`thread_`).
- `LocalPriceManager.cpp`: `GetQuotes :72` (asserts `!strand_.running_in_this_thread()` at `:78`, posts at `:89`); `DispatchBatchOnStrand :162`; tier walk `:180-230` (`coinGeckoTier_->FetchPrices :192`, results appended to `fetched :197`; `gnusServiceTier_->FetchPrices :214`, `:219`); per-waiter assembly `:239-254`; `StoreInL1 :348`. **Record point:** immediately after the walk where `fetched` is final (before per-waiter assembly ~`:239`), looping `fetched` and appending quotes with `asset=="genius-ai"` (D-05: only `genius-ai`) — or all assets filtered at query time; recommend recording all fetched quotes keyed by asset+currency but D-05 says genius-ai, so filter on record.
- `src/processing/proto/SGProcessing.proto` Task: fields 1-5 `ipfs_block_id, json_data, random_seed(float), results_channel, escrow_path`. New: `double claimed_price = 6; // USD per genius-ai used to size the escrow`.
- `src/account/proto/SGTransaction.proto`: `DAGStruct.timestamp` int64 `:11`; `EscrowTx` at `:120`, `amount = 3` at `:124`.
- Tests calling `GetProcessCost` (will break on return type change, must update): `test/src/account/account_management_test.cpp`, `test/src/processing_multi/processing_multi_test.cpp`, `test/src/processing_nodes/child_tokens_test.cpp`, `test/src/processing_nodes/processing_nodes_test.cpp`.
- Existing price tests: `test/src/price_manager/price_manager_test.cpp` (+ `CMakeLists.txt` there), `price_facade/price_facade_test.cpp`, `price_quote`, `price_retrieval`, `price_http_client`.

### Pattern 1: GetProcessCost struct return
```cpp
struct ProcessCost { uint64_t minions = 0; PriceQuote quote; };
// failure keeps today's "0 minions" convention so `funds <= 0` check survives:
ProcessCost GeniusNode::GetProcessCost(const ProcessingManager&);   // minions==0 => error
// ProcessImage:
auto cost = GetProcessCost(*procmgr);
if (cost.minions <= 0) return outcome::failure(Error::PROCESS_COST_ERROR);
...
task.set_claimed_price(cost.quote.price);
```
Keeps header-visible change minimal, but any test using `uint64_t x = GetProcessCost(..)` must use `.minions`. Alternative: keep `uint64_t GetProcessCost` as wrapper and add `GetProcessCostQuoted` — lower churn for the 4 test files; **recommend this** if D-06-01 ("returns a struct") allows planner to rename; otherwise update the 4 tests mechanically.

### Pattern 2: History ring in the strand
```cpp
struct PriceObservation { std::chrono::system_clock::time_point at; double price; PriceSource source; };
struct PriceHistoryStats { size_t count=0; double min=0, max=0; };
struct PriceHistoryConfig { std::chrono::seconds retention{24*3600}; size_t maxEntries = 4096; };
std::deque<PriceObservation> history_;   // strand-confined, append-only, time-ordered
void RecordObservations(const std::vector<PriceQuote>&);   // strand; prune by retention (vs now_()) and cap
PriceHistoryStats QueryHistory(from, to);   // blocking post+future, like GetQuotes
```
Use `quote.timestamp` (fetch time, D-14) as the observation time; prune using injected `now_` so tests are hermetic. Pass config via an optional ctor param with a default (keeps existing ctor call sites `make_shared<LocalPriceManager>(tier1,tier2)` valid — add AFTER `now`).

### Anti-patterns
- Second `GetGNUSPrice()` call in ProcessImage (violates WIRE-02).
- Recording in `StoreInL1` or `HandleRequestOnStrand` hit path (StoreInL1 is also the right place only if L1 hits never call it — confirm; safer to record in the walk).
- Mutex on history (class is strand-confined, "not a single mutex").
- Calling `QueryHistory` from the runner thread (self-deadlock; mirror assert at `:78`).
- Using `float` for the proto field (random_seed is float; price must be `double` — float loses precision and would break Phase 7 `CalculateCostMinions(size, claimed) == escrow` equality).

## Don't Hand-Roll
| Problem | Use Instead |
|---------|-------------|
| Serialization | protobuf-generated `set_claimed_price` / `claimed_price()` |
| Thread safety for history | existing strand + post/future bridge |
| Time in tests | existing injectable `Clock now` |
| Cost computation | `TokenAmount::CalculateCostMinions` |

## Runtime State Inventory
Not a rename/migration phase — omitted. Note on wire compat: adding proto3 field 6 is backward compatible; old nodes ignore it; tasks from old nodes read `claimed_price()==0.0` (proto3 default) — Phase 7 legacy policy must treat 0 as "absent" (cannot distinguish absent from 0; price<=0 is never valid anyway since `GetGNUSPrice` rejects <=0). Consider `optional double` if presence needed — [ASSUMED] not required.

## Common Pitfalls
1. **Float vs double** on wire (above). Use `double`.
2. **Double-read race**: price read twice yields claim ≠ escrow sizing. Single quote through struct.
3. **Recording cache hits** inflates history with duplicate stale values; record only in tier-success walk.
4. **Quote timestamp vs now**: `PriceQuote.timestamp` is fetch time; a tier (Worker envelope) may return its own `fetchedAt` older than now. Record `quote.timestamp` as observed time but note dedupe: identical quote returned by gnus tier on repeated fetch yields repeated entries with the same timestamp — consider skipping consecutive entries with identical (timestamp, price). [ASSUMED] design choice.
5. **Pruning with std::deque**: prune from front; because `timestamp` may be non-monotonic across tiers, do not binary-search blindly — linear scan for min/max/count over window (≤ count cap, cheap).
6. **Member declaration order** in LocalPriceManager (thread_ last) — put new members before `thread_`.
7. **Existing tests break** on `GetProcessCost` return type (4 files) — see anchors.
8. **Proto regeneration**: other language/SDK consumers of SGProcessing.proto (GeniusSDK, wallet) just regenerate; field is additive. Grep other copies of the proto before finishing [not verified].
9. **Windows PowerShell**: build/test commands in repo docs are bash/cmake; use the project's existing build dirs.
10. Don't use `float` equality in tests for price; use exact `double` since value is copied, not computed.

## Code Examples
```proto
message Task {
    ...
    string escrow_path     = 5;
    double claimed_price   = 6; // USD per genius-ai used to size the escrow (single-read with cost)
}
```
```cpp
// LocalPriceManager::DispatchBatchOnStrand, after walk (~:230):
RecordObservations( fetched );   // fetched = network-tier quotes only
```

## State of the Art
Phases 3/4 delivered the quote surface; Phase 6 adds provenance on the wire. No external library changes.

## Assumptions Log
| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `optional double` presence not needed | Runtime State | Phase 7 cannot tell absent from 0 — mitigated since 0 invalid |
| A2 | Dedupe identical consecutive observations is desirable | Pitfalls | count semantics for Phase 7 coverage differ |
| A3 | No other copies of SGProcessing.proto need edits | Pitfalls | build break in SDK |
| A4 | `set_escrow_path` location/order relative to stamp irrelevant | Anchors | none expected |
| A5 | Config key naming (e.g. `price_history_retention_s`, `price_history_max_entries`) | Pattern 2 | discretion |

## Open Questions
1. Struct return vs wrapper (4 tests churn) — planner picks; recommend wrapper-preserving approach if D-06-01 wording allows.
2. Record only `genius-ai` (D-05) — hard-code or configurable asset set? Recommend hard-code constant `"genius-ai"`.
3. Which currency to record — only "usd" path used today.

## Environment Availability
No new external deps. Build uses existing CMake/vcpkg-style toolchain; hermetic tests use stub tiers (IPriceSource) and need no network. Windows host here; actual build/test run not performed this session.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | GoogleTest (existing) |
| Config | `SuperGenius/test/src/price_manager/CMakeLists.txt` (existing target) |
| Quick run | the existing price_manager test binary (`--gtest_filter=*History*`) |
| Full suite | existing price_* test targets + processing tests using GetProcessCost |

### Phase Requirements → Test Map
| Req | Behavior | Type | Command / File | Exists |
|-----|----------|------|----------------|--------|
| WIRE-01 | Task round-trips `claimed_price` (serialize/parse equals, default 0 when unset) | unit | new test in `test/src/price_quote` or processing proto test | ❌ Wave 0 |
| WIRE-02 | Stub tier price P; `GetProcessCost` quote.price==P and minions==`CalculateCostMinions(size,P)`; ProcessImage task claimed_price==P; price changing between two stub fetches doesn't desync (stub returns P1 then P2; claim==P1 and escrow sized by P1) | integration (hermetic, Phase 4 harness) | `test/src/account/account_management_test.cpp` area | ❌ Wave 0 |
| HIST-01 | Network fetches recorded; L1 hit not recorded (stub call count vs history count); min/max/count over window; retention prune via injected clock; count cap evicts oldest; only genius-ai | unit | `price_manager_test.cpp` | ❌ Wave 0 |
| HIST-02 | Fresh manager: query returns count 0; new manager instance empty (no persistence) | unit | `price_manager_test.cpp` | ❌ Wave 0 |

### Sampling
- Per commit: price_manager tests; per wave: all price_* plus the 4 processing test files compile+run; phase gate: full suite green.

### Wave 0 Gaps
- [ ] History tests in `price_manager_test.cpp` (stub IPriceSource, injected Clock)
- [ ] Proto round-trip test
- [ ] Update the 4 `GetProcessCost` callers if signature changes
- [ ] Concurrency test: concurrent GetQuotes + QueryHistory under TSAN-style stress (no data race since strand)

## Security Domain
| ASVS | Applies | Control |
|------|---------|---------|
| V5 Input validation | yes (Phase 7 consumes) | Claimed price is untrusted on receive; Phase 6 only emits. Poster-set value; do not trust in logic added here |
| V2/V3/V4/V6 | no | — |

Threats: poster forges `claimed_price` (Tampering) — mitigated by Phase 7 validation, not here; unbounded memory growth from history (DoS) — mitigated by count cap + retention; history values must not be logged at high volume.

## Sources
- Primary (read this session): files listed under Code anchors; 06-CONTEXT.md, STATE.md. REQUIREMENTS.md/ROADMAP.md and prior-phase RESEARCH/PATTERNS docs were NOT fully read (tool-output truncation); CONTEXT supersedes their timestamp wording anyway.
- No web/Context7 lookups were needed; no packages added.

## Metadata
**Research date:** 2026-10-05 | **Valid until:** ~30 days (internal code; re-verify line numbers after edits)
