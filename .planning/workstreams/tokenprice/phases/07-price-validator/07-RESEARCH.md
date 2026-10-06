# Phase 7: Price Validator - Research

**Researched:** 2026-10-06
**Domain:** Deterministic pure-function price validation (C++17, SuperGenius `src/coinprices/`) — timestamp sanity, tolerance-band check, escrow cost binding, typed reject reasons, hermetic gtest suite
**Confidence:** HIGH

<user_constraints>

## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-07-01 Tolerance:** default **10%** — each node widens its observed window `[min, max]` by ±10%. Chosen over 5% (OQ2's tentative value) because genius-ai is a volatile low-cap token and the tolerance only needs to absorb cross-node fetch-moment variance, not intra-window market movement; 10% still catches deliberate gaming. — **Reversibility:** reversible — a constant in `PriceValidatorConfig`.
- **D-07-02 Window:** **asymmetric `[T − (quote TTL + skew), T + skew]`** around the escrow DAG timestamp T, where quote TTL = `kStaleMaxAge` (300s) from `PriceFreshness.hpp`. Exactly D-06-03: minimal dead band, smallest cherry-picking surface. Not the symmetric ±10 min suggested in OQ2 — prices *after* T could not have been used by the poster. — **Reversibility:** reversible.
- **D-07-03 Timestamp bounds:** clock skew allowance **30s** (within one freshness band), max age **10 min** relative to when the validator runs. A 10-min-old escrow is beyond any quote TTL, so an honest poster's T always passes the age check. — **Reversibility:** reversible.
- **D-07-04 Configuration:** `PriceValidatorConfig` plain struct with code defaults, overridable via **`SGNS_PRICEVAL_*` environment variables** — matching the Phase 4 env-var precedent (`SGNS_CONSOLE_LOG_TESTS`/`SGNS_DEBUGLOGS`, Phase 4 D-01). `GeniusNodeConfig` stays untouched (brace-initialized aggregate). All four knobs (tolerance, window width, skew, max age) documented with these defaults per VAL-02. — **Reversibility:** reversible.
- **D-07-05 Verdict:** `QueryHistory` returns `count == 0` over the window → **reject with `NO_COVERAGE`**. Deterministic and fail-closed; the typed reason distinguishes "unverifiable" from "gamed" for Phase 8 logging/telemetry. A node with no evidence does not vouch for a job. Fetch-and-widen was rejected because a fresh quote is not from time T and makes the verdict timing-dependent (breaks the determinism Phase 8 convergence needs); defer was rejected because it introduces a third state the consensus hook would have to handle.
- **D-07-06 Self-heal:** the *verdict* stands, but on `NO_COVERAGE` the node triggers a **background fetch** via `LocalPriceManager` so subsequent tasks regain coverage within one fetch cycle. The self-heal trigger is a caller-side side effect — the validator function itself stays pure (returns the verdict; the Phase 8 caller observes the reason and fetches).
- **D-07-07 Minimum coverage:** `count >= 1` is coverage. A single observation is still evidence; the market moving >10% within the 300s lookback is rare, and the alternative (requiring 2+) would make rarely-fetching nodes reject almost everything.
- **D-07-08 Verdict:** `claimed_price == 0.0` (proto3 default, field absent) → **reject with `LEGACY_NO_PRICE`**. Fail-closed from day one: no grace flag to remove later, no window where gaming-via-missing-field is possible. — **Reversibility:** one-way — once Phase 8 enforces rejection network-wide, reverting to a grace/accept policy changes consensus-visible behavior for legacy messages.
- **D-07-09 Rollout:** **hard cutover**, no log-only shakedown period. The network is young; posters and validators ship together in the same SuperGenius node release, so stale posters are rare and self-inflicted. Simplicity beats migration machinery.
- **D-07-10 Return type:** `struct { bool accepted; Reason reason; ...diagnostics }` — a typed enum (`Reason`) for control flow plus the computed band / observed stats carried in the struct, so Phase 8 logging and tests assert details without re-deriving them. Not `outcome::result` error codes (accept is the common case, not success-vs-error) and not enum-only (forces callers to recompute the band to log why). — **Reversibility:** costly — Phase 8 will consume this API; changing the shape after integration touches the consensus path.
- **D-07-11 Check order:** fixed fail-fast chain **legacy → timestamp sanity → cost binding → band**. Cheapest/most structural checks first; the first three need no history query at all; exactly one reason per input — deterministic and easy to test. Cost binding runs before the band check (an honest-price/lowered-escrow attack fails on cost binding with its specific reason).
- **D-07-12 Home & input:** **free function in `SuperGenius/src/coinprices/`** taking a `PriceValidationInput` struct: `claimed_price` (double), escrow amount (uint64), DAG timestamp, blockSize (uint64), and the already-aggregated `PriceHistoryStats{count, min, max}`. The caller (GeniusNode, Phase 8) performs the `QueryHistory` and escrow fetch. The validator depends on nothing but `TokenAmount` + the stats struct → hermetically testable with zero mocks. Reason enum values: `Accepted`, `LegacyNoPrice`, `TimestampFuture`, `TimestampStale`, `CostMismatch`, `AboveBand`, `BelowBand`, `NoCoverage`. — **Reversibility:** reversible (file placement) / costly (input struct after Phase 8 wiring).

### Agent's Discretion

Exact file names (e.g., `PriceValidator.hpp/.cpp` vs a header-only header), `Reason` enum spelling, diagnostics field set, env-var key names beyond the `SGNS_PRICEVAL_` prefix, test file organization under `test/src/coinprices/`, and whether the self-heal helper (D-07-06) lands as a small free function beside the validator or inline in the Phase 8 caller.

### Deferred Ideas (OUT OF SCOPE)

- Trust/reputation for repeat bad-actor posters and consensus-applied penalties (carried from Phase 6; later milestone).
- Tolerance/window defaults derived from real GNUS volatility telemetry (revisit D-07-01/02 defaults once mainnet data exists; config knobs make this tunable without code change).
- "Fix Vulkan capability-probe deadlock/crash in ProcessingManager::Create path" — keyword-only match ("validator"), unrelated domain; remains an open testing todo in its own right.

**Phase boundary (from CONTEXT domain):** NOT in this phase — consensus wiring (Phase 8), escrow refund (Phase 8), multi-node integration TEST-02 (Phase 8), wire/proto changes (Phase 6 shipped), pricing-formula changes, token.gnus.ai Worker changes.

</user_constraints>

<phase_requirements>

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| VAL-01 | Pure validator function: timestamp sanity (D-03), tolerance-band check against observed window (D-01), and cost-binding check (D-02), returning accept/reject with a typed reason | All three check inputs verified: `CalculateCostMinions(uint64_t,double)->outcome::result<uint64_t>` [VERIFIED: src/account/TokenAmount.hpp:105-114], `QueryHistory(from,to)->PriceHistoryStats` inclusive both ends [VERIFIED: src/coinprices/LocalPriceManager.hpp:126-135], `DAGStruct.timestamp` int64 field 5 / `EscrowTx.amount` uint64 field 3 [VERIFIED: src/account/proto/SGTransaction.proto:5-11,120-125]. Skeleton in Code Examples. `now` must be an input (Open Question Q1). NaN guard required (Pitfall 1) |
| VAL-02 | Tolerance %, window width, max age and clock skew are configurable with documented defaults | `PriceValidatorConfig` struct + `SGNS_PRICEVAL_*` env overrides follow the verified `PriceEndpoints.hpp` header-only `std::getenv` pattern [VERIFIED: src/coinprices/PriceEndpoints.hpp]; named-constant publication follows `PriceFreshness.hpp` `inline constexpr` pattern [VERIFIED: PriceFreshness.hpp:9-10]. Window-knob semantics ambiguity → Open Question Q2 |
| VAL-03 | Insufficient-coverage policy when the validator has no observations near `price_timestamp` is defined and tested | Locked by D-07-05 (reject `NO_COVERAGE` on `count == 0`), D-07-06 (caller-side self-heal fetch via `GetQuotes({"genius-ai"})` seam), D-07-07 (`count >= 1` is coverage). `PriceHistoryStats{count=0,min=0,max=0}` default verified [VERIFIED: LocalPriceManager.hpp:59-66] — key on `count`, never on `min/max` (Pitfall 2) |
| VAL-04 | Legacy tasks without the new fields have a defined policy | Locked by D-07-08 (`claimed_price == 0.0` → reject `LEGACY_NO_PRICE`; proto3 default for absent field verified in the proto comment [VERIFIED: SGProcessing.proto:13-23]) and D-07-09 (hard cutover). IEEE note: `-0.0 == 0.0` is true, so negative-zero also lands here [ASSUMED] |
| TEST-01 | Hermetic unit tests: in-band, out-of-band (high/low), future/stale timestamp, cost mismatch, no-coverage, legacy | Precedent verified: `price_manager_test.cpp` fixed-epoch `kEpochBase` pattern, zero sockets/mocks [VERIFIED: test/src/price_manager/price_manager_test.cpp:30-35]; `addtest()` macro auto-links GTest/gmock, 600s timeout, xunit XML [VERIFIED: cmake/functions.cmake:8-45]; build command precedent [VERIFIED: 06-02-PLAN.md:84]. Link wiring for `TokenAmount` resolved in Pitfall 5 / Architecture Patterns |

</phase_requirements>

## Summary

Phase 7 builds a **pure, deterministic validator free function** in `SuperGenius/src/coinprices/` plus its config struct, its env-var overrides, and a hermetic gtest suite. Every input it consumes already exists and was read this session: the wire carries `Task.claimed_price` (double, field 6) [VERIFIED: src/processing/proto/SGProcessing.proto:23]; the reference time is the escrow `DAGStruct.timestamp` (int64, field 5) with the escrowed amount in `EscrowTx.amount` (uint64, field 3) [VERIFIED: src/account/proto/SGTransaction.proto:11,120-125]; the evidence is `LocalPriceManager::QueryHistory(from, to)` returning `PriceHistoryStats{count, min, max}` with `[from, to]` **inclusive both ends** and `count==0` meaning no-coverage-not-error [VERIFIED: src/coinprices/LocalPriceManager.hpp:59-66,126-135]; and the cost-binding oracle is `TokenAmount::CalculateCostMinions(uint64_t total_bytes, double price_usd_per_genius) -> outcome::result<uint64_t>` [VERIFIED: src/account/TokenAmount.hpp:105-114]. The poster-side stamping (`task.set_claimed_price( cost.quote.price )` from the same quote that sized the escrow) is already live in `GeniusNode::ProcessImage` [VERIFIED: src/account/GeniusNode.cpp:2720], so recomputation over the same double is exact — protobuf doubles are bit-preserved and `CalculateCostMinions` is a pure function, making **integer equality the correct cost-binding comparison** (no epsilon).

Cost-binding exactness holds because the poster's flow is: `ParseBlockSize()` → `GetGNUSQuote()` → `CalculateCostMinions( blockLen.value(), gnusPrice )` → escrow `rawMinions` and stamp `cost.quote.price` [VERIFIED: GeniusNode.cpp:2816-2847]. The Phase 8 caller reproduces `blockSize` the same way; this phase takes it as a plain `uint64_t` input. The one real correctness hazard found is **NaN**: `ScaledInteger::FromDouble`'s guard `if ( rounded < 0.0 || rounded > ...max() )` does not exclude NaN (NaN comparisons are false), so a NaN `claimed_price` reaches `static_cast<uint64_t>(NaN)` — undefined behavior and non-portable across nodes [VERIFIED guard: src/base/ScaledInteger.cpp; UB claim: ASSUMED]. The validator must reject non-finite prices explicitly before cost binding (Pitfall 1). The one real build hazard is the **library cycle**: `TokenAmount.cpp` compiles into `genius_node_objs`, whose `GENIUS_NODE_LIBS` already links `coinprices` [VERIFIED: src/account/CMakeLists.txt:84,91-92; src/CMakeLists.txt:4-21], so `coinprices` must never declare a link back — rely on static-archive semantics (`BUILD_SHARED_LIBS` default OFF) and let the final executable resolve the symbol (Pitfall 5).

**Primary recommendation:** Implement `PriceValidator.hpp/.cpp` in `src/coinprices/` as `ValidatePrice(PriceValidationInput, PriceValidatorConfig) -> PriceValidationResult` with `now` added to the input struct, an explicit non-finite/negative guard folded into the fail-fast chain, defaults published as `inline constexpr` named constants (reusing `kStaleMaxAge`), env overrides in a header-only `PriceValidatorConfig.hpp` following `PriceEndpoints.hpp`, a window-derivation helper so caller and validator share one window formula, and a new `price_validator_test` target under `test/src/price_validator/` linking `coinprices` + `genius_node_test`.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Accept/reject decision + typed reason | Domain logic (`src/coinprices/` pure function) | — | Deterministic, hermetically testable, zero I/O; D-07-12 locks the home |
| Threshold defaults & env overrides | Domain logic (`PriceValidatorConfig`, header-only getenv) | — | Phase 4 `PriceEndpoints.hpp` precedent; D-07-04 locks mechanism |
| Price observation window query (`min/max/count`) | Data layer (`LocalPriceManager::QueryHistory`, blocking strand bridge) | — | Evidence aggregation already owned there (HIST-01); caller-side per D-07-12 |
| Escrow amount + DAG timestamp retrieval | Data layer (`TransactionManager::FetchTransaction(globaldb, escrow_path)`) | — | Phase 8 caller concern; shapes `PriceValidationInput` fields only |
| Cost recomputation | Domain logic (`TokenAmount::CalculateCostMinions`) | — | D-02/D-07-12; never re-implement the formula |
| Self-heal fetch on NO_COVERAGE | Service layer (Phase 8 caller invokes `GetQuotes({"genius-ai"})`) | — | D-07-06: caller-side side effect keeps validator pure |
| Consensus enforcement of verdicts | Consensus/processing path (Phase 8) | — | Explicitly out of this phase's boundary |

## Standard Stack

No new third-party packages. This phase composes existing in-repo building blocks only.

### Core (all in-repo, verified this session)

| Component | Location | Purpose | Verified Signature / Fact |
|-----------|----------|---------|---------------------------|
| `TokenAmount::CalculateCostMinions` | `src/account/TokenAmount.{hpp,cpp}` | Cost-binding oracle (D-02) | `static outcome::result<uint64_t> CalculateCostMinions( uint64_t total_bytes, double price_usd_per_genius );` [VERIFIED: TokenAmount.hpp:105-114]; floors at `raw_minions = std::max( raw_minions, MIN_MINION_UNITS );` with `MIN_MINION_UNITS = 1` [VERIFIED: TokenAmount.cpp:100-101, TokenAmount.hpp:41]; failure path returns `std::errc::value_too_large` [VERIFIED: TokenAmount.cpp:95] |
| `LocalPriceManager::QueryHistory` | `src/coinprices/LocalPriceManager.hpp` | Evidence input: `min/max/count` over window | `PriceHistoryStats QueryHistory( std::chrono::system_clock::time_point from, std::chrono::system_clock::time_point to );` — "fetch time lies in [from, to] (inclusive both ends)"; "empty or no-coverage window returns count==0 with no error" [VERIFIED: LocalPriceManager.hpp:126-135] |
| `PriceHistoryStats` | `src/coinprices/LocalPriceManager.hpp` | Reuse as the validator's evidence type | `struct PriceHistoryStats { size_t count = 0; double min = 0.0; double max = 0.0; };` [VERIFIED: LocalPriceManager.hpp:59-66] |
| `kStaleMaxAge` / `kFreshMaxAge` | `src/coinprices/PriceFreshness.hpp` | Quote TTL feeding window width (D-07-02) | `inline constexpr std::chrono::seconds kFreshMaxAge{ 60 };` / `inline constexpr std::chrono::seconds kStaleMaxAge{ 300 };` [VERIFIED: PriceFreshness.hpp:9-10] |
| `ScaledInteger::FromDouble` | `src/base/ScaledInteger.cpp` | Underlies double→fixed conversion; NaN hazard | `if ( rounded < 0.0 || rounded > static_cast<double>( std::numeric_limits<uint64_t>::max() ) ) { return outcome::failure( std::make_error_code( std::errc::value_too_large ) ); }` [VERIFIED: ScaledInteger.cpp, FromDouble] |
| GTest + outcome macros | `test/testutil/outcome.hpp`, `addtest()` | Test framework | `EXPECT_OUTCOME_TRUE(val, expr)` / `EXPECT_OUTCOME_FALSE(val, expr)` macros [VERIFIED: test/testutil/outcome.hpp]; `addtest` links `GTest::gtest_main` + `GTest::gmock_main`, `TIMEOUT 600`, xunit XML, outputs to `test_bin` [VERIFIED: cmake/functions.cmake:8-45] |

**Installation:** none. C++17 (`set(CMAKE_CXX_STANDARD 17)` + `CMAKE_CXX_STANDARD_REQUIRED ON`) [VERIFIED: build/CommonCompilerOptions.cmake:6-7].

## Package Legitimacy Audit

No external packages are installed or recommended in this phase — all dependencies are in-repo targets (`coinprices`, `genius_node_test`, GTest already vendored/wired).

| Package | Registry | Age | Downloads | Source Repo | Verdict | Disposition |
|---------|----------|-----|-----------|-------------|---------|-------------|
| — | — | — | — | — | — | none — no external packages |

**Packages removed due to [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

## Architecture Patterns

### System Architecture Diagram

```mermaid
flowchart TD
    subgraph Poster["Poster node (Phase 6, shipped)"]
        A[ProcessImage] -->|"ParseBlockSize()"| B[blockSize uint64]
        A -->|"GetGNUSQuote() one read"| C[PriceQuote double]
        C --> D["CalculateCostMinions(size, price)"]
        D --> E["escrow amount uint64<br/>(EscrowTx.amount)"]
        C --> F["Task.claimed_price = 6 (double)"]
        E --> G["escrow tx DAG<br/>DAGStruct.timestamp = T"]
    end

    subgraph ValidatorNode["Validator node (THIS PHASE)"]
        H["Caller (Phase 8) —<br/>NOT this phase"] -->|"FetchTransaction(escrow_path)"| G
        H -->|"QueryHistory(from, to)<br/>from = T − (ttl + skew), to = T + skew"| I[PriceHistoryStats<br/>count/min/max]
        H --> J["PriceValidationInput<br/>{claimed_price, escrow_amount, T,<br/>blockSize, now, stats}"]
        J --> K{ValidatePrice(input, config)<br/>PURE free function}
    end

    F --> J
    K -->|"1. claimed_price == 0.0"| L[LegacyNoPrice]
    K -->|"2. T > now+skew / T < now−maxAge"| M[TimestampFuture / TimestampStale]
    K -->|"3. CalculateCostMinions(size,<br/>claimed) != escrow_amount"| N[CostMismatch]
    K -->|"4. count == 0"| O[NoCoverage → caller<br/>self-heal fetch]
    K -->|"4. claimed ∉ [min·(1−tol), max·(1+tol)]"| P[AboveBand / BelowBand]
    K -->|all pass| Q[Accepted]
```

A reader traces the primary use case: wire double + escrow amount + DAG timestamp enter the pure function (checks 1–3 need no history), then the caller-supplied window stats drive the band check; exactly one reason emerges per D-07-11 order.

### Recommended Project Structure

```
SuperGenius/src/coinprices/
├── PriceValidator.hpp      # Reason enum, PriceValidationInput, PriceValidationResult,
│                           #   PriceValidatorConfig + inline constexpr defaults, ValidatePrice decl,
│                           #   window-derivation helper (from/to for QueryHistory)
├── PriceValidator.cpp      # fail-fast chain implementation (added to coinprices target)
└── (existing files untouched)

SuperGenius/test/src/price_validator/
├── CMakeLists.txt          # addtest(price_validator_test price_validator_test.cpp); link coinprices
│                           #   + genius_node_test + AsyncIOManager include dir (precedent: price_manager)
└── price_validator_test.cpp  # fixed-epoch struct-literal tests, one per reason + boundaries
```
(File names are agent's discretion per CONTEXT; `price_validator` dir name follows the existing `test/src/price_*` convention rather than the non-existent `test/src/coinprices/` — CONTEXT allows discretion here.)

### Pattern 1: Pure function + plain-struct inputs (fail-fast chain)
**What:** One free function, no classes, no I/O, no clocks — every external fact (including `now`) arrives as a value.
**When to use:** Always in this phase; determinism is a Phase 8 prerequisite (CONS-02).
**Why:** `price_manager_test.cpp` proves the hermetic pattern: "Fixed epoch base for all timestamp arithmetic — no `system_clock::now()` anywhere in this suite" [VERIFIED: price_manager_test.cpp:31-33].

### Pattern 2: Config struct + header-only getenv override (Phase 4 precedent)
**What:** Code defaults as `inline constexpr`; env read via tiny free functions; read NOT cached in a function-local static.
**When to use:** `PriceValidatorConfig` resolution (VAL-02, D-07-04).
**Example — the exact precedent** [VERIFIED: src/coinprices/PriceEndpoints.hpp]:
```cpp
// Source: SuperGenius/src/coinprices/PriceEndpoints.hpp (verbatim behavior)
inline std::string GetPriceBaseUrl( const char *envName, const char *productionDefault )
{
    const char *env = std::getenv( envName );
    if ( env != nullptr && *env != '\0' )
    {
        return std::string( env );
    }
    return std::string( productionDefault );
}
```
Apply the same shape for `SGNS_PRICEVAL_TOLERANCE_PCT`, `SGNS_PRICEVAL_WINDOW_TTL_S`, `SGNS_PRICEVAL_CLOCK_SKEW_S`, `SGNS_PRICEVAL_MAX_AGE_S` (exact names are discretion; parse percent as double, seconds as integer).

### Pattern 3: Named shared constants consumed by code and tests
**What:** Publish defaults exactly as `PriceFreshness.hpp` does — `inline constexpr` in the header, tests reference the symbol, never a literal.
**When to use:** tolerance `0.10`, skew `30s`, max age `600s`, window TTL default = `kStaleMaxAge` (reuse, don't restate — DRY).
**Precedent** [VERIFIED: PriceFreshness.hpp:8-10]: `inline constexpr std::chrono::seconds kFreshMaxAge{ 60 };` / `inline constexpr std::chrono::seconds kStaleMaxAge{ 300 };`

### Pattern 4: One source of truth for the observation window
**What:** The validator header exposes a tiny pure helper returning the `{from, to}` pair: `from = T − (windowTtl + skew)`, `to = T + skew` (D-07-02). The Phase 8 caller calls it before `QueryHistory`; the validator itself consumes only the already-queried stats.
**When to use:** Immediately — ship it in this phase so caller and any test share one formula (CLAUDE.md hard invariant #2: never duplicate a rule).
**Note:** `QueryHistory` bounds are inclusive both ends [VERIFIED: LocalPriceManager.hpp:129-131], so the helper's bounds need no adjustment.

### Anti-Patterns to Avoid
- **Epsilon-comparing the cost:** the whole point of Phase 6's "double, never float" decision (STATE.md Decisions) is that `CalculateCostMinions(size, claimed_price)` over a bit-identical double yields an identical uint64 — compare integers with `==`, never `fabs(a-b) < eps` on costs.
- **Keying no-coverage on `min == 0`:** `PriceHistoryStats` defaults `min = 0.0` but a covered window could theoretically contain low quotes; `count == 0` is the semantic key [VERIFIED: LocalPriceManager.hpp:61-66 "count==0 means 'no coverage' — not an error"].
- **Reading the clock inside the validator:** breaks purity/hermetic tests; `now` is an input (see Open Question Q1).
- **Declaring `coinprices → genius_node*` CMake link:** creates the cycle `genius_node_objs → coinprices` already present in `GENIUS_NODE_LIBS` [VERIFIED: src/CMakeLists.txt:4-21].
- **Adding a third verdict state (defer/pending):** explicitly rejected in D-07-05 — binary accept/reject with typed reasons only.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Cost formula | Re-derive minions from bytes/price | `TokenAmount::CalculateCostMinions` | Fixed-precision ScaledInteger walk with precision loop, `MIN_MINION_UNITS` floor, overflow guards [VERIFIED: TokenAmount.cpp:65-107] — any reimplementation drifts and breaks D-02 equality |
| Window min/max aggregation | Iterate history yourself | `LocalPriceManager::QueryHistory` | Strand-confined, inclusive-bounds semantics already tested (HIST-01) [VERIFIED: LocalPriceManager.hpp:126-135] |
| Quote TTL constant | Redefine 300s | `kStaleMaxAge` | One home per threshold (CLAUDE.md invariant #2); already consumed by code and tests [VERIFIED: PriceFreshness.hpp:9-10] |
| Env-var resolution | Ad-hoc getenv sprinkled in the chain | One resolver per knob, `PriceEndpoints.hpp` shape | Null/empty/unset semantics settled once; no function-local static caching [VERIFIED: PriceEndpoints.hpp] |
| Result/reason plumbing | Exceptions, `outcome::result` for the verdict, bool-only return | `struct { bool accepted; Reason reason; ...diagnostics }` | D-07-10 locked: accept is the common case, not success-vs-error; diagnostics avoid Phase 8 re-derivation |

**Key insight:** every hand-roll risk here is a *determinism* risk — two nodes computing a verdict differently is a Phase 8 consensus split, the most expensive failure mode this milestone has.

## Common Pitfalls

### Pitfall 1: NaN claimed_price slips through FromDouble into UB
**What goes wrong:** A malicious poster controls the wire double's bits and can send NaN. `ScaledInteger::FromDouble`'s guard — `if ( rounded < 0.0 || rounded > static_cast<double>( std::numeric_limits<uint64_t>::max() ) )` [VERIFIED: src/base/ScaledInteger.cpp] — does not catch NaN, because every NaN comparison is false [ASSUMED — IEEE-754 semantics]. Execution reaches `static_cast<uint64_t>(NaN)`, which is undefined behavior and platform-dependent (typically 0 or 0x8000…0 on x64) [ASSUMED] — two nodes on different platforms could produce different verdicts, breaking CONS-02 determinism.
**How to avoid:** Before cost binding, reject non-finite / negative prices explicitly: `if ( claimed_price == 0.0 ) → LegacyNoPrice;` then `if ( !std::isfinite( claimed_price ) || claimed_price < 0.0 ) → CostMismatch;` (deterministic rejection without entering `CalculateCostMinions`). Note `+inf` already fails the FromDouble guard deterministically, but rejecting all non-finites up front is cheaper and clearer. The enum is locked (D-07-12) so `CostMismatch` is the correct bucket — document it.
**Warning signs:** a test feeding `std::numeric_limits<double>::quiet_NaN()` that returns `AboveBand`/`BelowBand` or, worse, `Accepted`.

### Pitfall 2: Confusing "no coverage" with "observed price 0"
**What goes wrong:** Testing `min`/`max` instead of `count` for coverage; or expecting `QueryHistory` to error on empty windows.
**Why:** `PriceHistoryStats` defaults are `count = 0; min = 0.0; max = 0.0` [VERIFIED: LocalPriceManager.hpp:59-66] and empty windows return `count==0` with **no error** [VERIFIED: LocalPriceManager.hpp:131-133].
**How to avoid:** The band check's no-coverage gate is `stats.count == 0 → NoCoverage` (D-07-05, D-07-07); `count >= 1` proceeds with the band check even if `min == max`.
**Warning signs:** any branch reading `stats.min` before checking `count`.

### Pitfall 3: Window knob semantics — TTL component vs total width
**What goes wrong:** D-07-04 names a "window width" knob, but D-07-02 defines the window as `[T − (quote TTL + skew), T + skew]`. If the knob means total lookback (330s default) in one place and TTL component (300s default) in another, caller and tests disagree by 30s at the window's left edge.
**How to avoid:** Pick one meaning and name it for it (recommendation: the knob is the **lookback TTL component**, default `kStaleMaxAge`, `from = T − (ttl + skew)` — see Open Question Q2). The window helper (Pattern 4) makes drift impossible because there is only one formula.
**Warning signs:** two constants that differ by exactly the skew value.

### Pitfall 4: Boundary inclusivity left implicit
**What goes wrong:** Tests assert strict-inequality behavior where the spec means inclusive (or vice versa) at four boundaries: band edges `min·(1−tol)`/`max·(1+tol)`, timestamp edges `now + skew` (future) and `now − maxAge` (stale), and window ends.
**Why:** `QueryHistory` is inclusive both ends [VERIFIED: LocalPriceManager.hpp:129-131]; `ClassifyFreshness` establishes the house convention — "bands are closed on the fresh side", `age == kFreshMaxAge` classifies Fresh [VERIFIED: PriceFreshness.hpp:19-21] — i.e. boundaries belong to the accept side.
**How to avoid:** Decide and document: recommend `T == now + skew` → still accepted (within skew), `T == now − maxAge` → still accepted (not yet stale), `claimed == min·(1−tol)` or `== max·(1+tol)` → accepted ("lies within" reads inclusive), and write an exact-boundary test for each. [ASSUMED — recommendation, not locked]
**Warning signs:** tests only use values comfortably inside/outside the band.

### Pitfall 5: The coinprices ↔ genius_node link cycle
**What goes wrong:** Adding `PriceValidator.cpp` to the `coinprices` target makes the archive reference `TokenAmount::CalculateCostMinions`, whose object file lives in `genius_node_objs` (`TokenAmount.cpp` is in `GENIUS_NODE_SOURCES`) [VERIFIED: src/account/CMakeLists.txt:84-96]; `GENIUS_NODE_LIBS` already links `coinprices` [VERIFIED: src/CMakeLists.txt:4-21]. Declaring `target_link_libraries(coinprices ... genius_node_objs)` produces a CMake cycle.
**How to avoid:** Do NOT declare the reverse link. `BUILD_SHARED_LIBS` defaults OFF (`option(BUILD_SHARED_LIBS "Build shared libraries" OFF)`; no override in the Release cache) [VERIFIED: evmrelay/cmake/CommonBuildParameters.cmake + CMakeCache.txt], so `coinprices` is a static archive: only executables that actually reference `ValidatePrice` pull `PriceValidator.obj` and must link `TokenAmount.o` — i.e. the validator test (link `genius_node_test`) and, in Phase 8, `genius_node` itself (already links both). `price_manager_test` keeps linking plain `coinprices` untouched because unreferenced archive members are never pulled. Cross-dir include works: `#include "account/TokenAmount.hpp"` resolves the same way `#include "base/logger.hpp"` does from coinprices today [VERIFIED: LocalPriceManager.hpp:20] — `src/` is an include root.
**Warning signs:** CMake "circular dependency" at generate time, or MSVC `LNK2019: unresolved external symbol ... CalculateCostMinions` on a target that references the validator but doesn't link `genius_node_test`/`genius_node`.

### Pitfall 6: Env-var caching freezing test overrides
**What goes wrong:** Wrapping getenv in a function-local static so the config is read once per process — then tests that set `SGNS_PRICEVAL_*` per-case see stale values.
**Why:** The precedent explicitly forbids it: "The read is intentionally NOT cached in a function-local static … a static would freeze the first value process-wide" [VERIFIED: PriceEndpoints.hpp:25-28].
**How to avoid:** Read env at `PriceValidatorConfig` resolution time (e.g., a `PriceValidatorConfig::FromEnv()` or free `ResolvePriceValidatorConfig()`), no statics. Tests that exercise env overrides set/restore the variable around one call (or prefer injecting the struct directly and unit-test the resolver separately — simplest hermetic shape: pass explicit configs everywhere in TEST-01 and give the resolver its own small test).

### Pitfall 7: Diagnostics re-derivation in tests/Phase 8
**What goes wrong:** Tests (and Phase 8 logging) recomputing the band `min·(1−tol)..max·(1+tol)` to explain a reject — a second copy of the formula that can drift.
**How to avoid:** D-07-10's struct carries the computed band and echoed stats (e.g., `observed_min`, `observed_max`, `band_low`, `band_high`, `window_from`, `window_to`); tests assert on the struct's fields, never re-derive.

## Code Examples

### Validator skeleton (types verified against sources read this session)

```cpp
// Source: signatures quoted verbatim from files read this session; skeleton itself is the recommended shape.
// SuperGenius/src/coinprices/PriceValidator.hpp
#pragma once
#include "coinprices/LocalPriceManager.hpp"   // PriceHistoryStats (reuse — D-07-12)
#include "coinprices/PriceFreshness.hpp"      // kStaleMaxAge
#include <chrono>

namespace sgns
{
    // Defaults published per the PriceFreshness.hpp inline-constexpr pattern.
    inline constexpr double                 kDefaultPriceTolerance{ 0.10 };      // D-07-01
    inline constexpr std::chrono::seconds   kDefaultValidatorClockSkew{ 30 };    // D-07-03
    inline constexpr std::chrono::seconds   kDefaultValidatorMaxAge{ 600 };      // D-07-03 (10 min)
    // Window TTL default = kStaleMaxAge{300} (quote TTL) — reuse, do not restate (D-07-02).

    enum class PriceValidationReason          // D-07-12 locked value set
    {
        Accepted, LegacyNoPrice, TimestampFuture, TimestampStale,
        CostMismatch, AboveBand, BelowBand, NoCoverage
    };

    struct PriceValidatorConfig               // D-07-04: plain struct, code defaults
    {
        double               tolerancePct = kDefaultPriceTolerance;
        std::chrono::seconds windowTtl    = kStaleMaxAge;      // see Open Question Q2
        std::chrono::seconds clockSkew    = kDefaultValidatorClockSkew;
        std::chrono::seconds maxAge       = kDefaultValidatorMaxAge;
    };

    struct PriceValidationInput               // D-07-12 fields + `now` (Open Question Q1)
    {
        double                               claimedPrice = 0.0;  // Task.claimed_price
        uint64_t                             escrowAmount = 0;    // EscrowTx.amount
        std::chrono::system_clock::time_point dagTimestamp{};     // DAGStruct.timestamp
        uint64_t                             blockSize    = 0;    // ParseBlockSize()
        std::chrono::system_clock::time_point now{};             // validator-run time (injected)
        LocalPriceManager::PriceHistoryStats stats{};            // QueryHistory(from,to)
    };

    struct PriceValidationResult             // D-07-10: struct + typed reason + diagnostics
    {
        bool                   accepted = false;
        PriceValidationReason  reason   = PriceValidationReason::Accepted;
        double                 bandLow  = 0.0;   // diagnostics: computed band (Pitfall 7)
        double                 bandHigh = 0.0;
        // ...echoed stats / window bounds per discretion
    };

    // One shared window formula (Pattern 4) — caller uses this for QueryHistory bounds.
    struct ObservationWindow { std::chrono::system_clock::time_point from, to; };
    ObservationWindow PriceObservationWindow(
        std::chrono::system_clock::time_point dagTimestamp,
        const PriceValidatorConfig           &config );   // from = T-(ttl+skew), to = T+skew

    PriceValidationResult ValidatePrice( const PriceValidationInput   &input,
                                         const PriceValidatorConfig &config = {} );
}
```

```cpp
// SuperGenius/src/coinprices/PriceValidator.cpp — fail-fast chain (D-07-11)
// Source: check semantics locked by D-07-05..D-07-12; guard details from verified sources.
#include "coinprices/PriceValidator.hpp"
#include "account/TokenAmount.hpp"   // resolves — src/ is an include root (base/logger precedent)
#include <cmath>                     // std::isfinite

namespace sgns
{
    PriceValidationResult ValidatePrice( const PriceValidationInput &input,
                                         const PriceValidatorConfig &config )
    {
        // 1. Legacy (D-07-08): proto3 default / absent field. Note -0.0 == 0.0 is true.
        if ( input.claimedPrice == 0.0 )
            return { false, PriceValidationReason::LegacyNoPrice, 0.0, 0.0 };

        // 2. Timestamp sanity (D-07-03), boundaries on the accept side (Pitfall 4).
        if ( input.dagTimestamp > input.now + config.clockSkew )
            return { false, PriceValidationReason::TimestampFuture, 0.0, 0.0 };
        if ( input.dagTimestamp < input.now - config.maxAge )
            return { false, PriceValidationReason::TimestampStale, 0.0, 0.0 };

        // 3. Cost binding (D-02/D-07-11): NaN guard BEFORE the oracle (Pitfall 1),
        //    integer equality — the double is bit-identical to the poster's (Phase 6 decision).
        if ( !std::isfinite( input.claimedPrice ) || input.claimedPrice < 0.0 )
            return { false, PriceValidationReason::CostMismatch, 0.0, 0.0 };
        auto expected = TokenAmount::CalculateCostMinions( input.blockSize, input.claimedPrice );
        if ( !expected || expected.value() != input.escrowAmount )
            return { false, PriceValidationReason::CostMismatch, 0.0, 0.0 };

        // 4. Coverage then band (D-07-05/D-07-07/D-07-01). Key on count, never min (Pitfall 2).
        if ( input.stats.count == 0 )
            return { false, PriceValidationReason::NoCoverage, 0.0, 0.0 };
        const double low  = input.stats.min * ( 1.0 - config.tolerancePct );
        const double high = input.stats.max * ( 1.0 + config.tolerancePct );
        if ( input.claimedPrice < low )
            return { false, PriceValidationReason::BelowBand, low, high };
        if ( input.claimedPrice > high )
            return { false, PriceValidationReason::AboveBand, low, high };
        return { true, PriceValidationReason::Accepted, low, high };
    }
}
```

### Test skeleton (hermetic — fixed epoch, struct literals, zero mocks)

```cpp
// Source: kEpochBase pattern quoted from test/src/price_manager/price_manager_test.cpp:31-33.
#include <gtest/gtest.h>
#include <coinprices/PriceValidator.hpp>
#include <cmath>

namespace
{
    const auto kEpochBase = std::chrono::system_clock::time_point{} + std::chrono::seconds( 1727712000 );

    PriceValidationInput BaseInput()  // every field a plain literal — TEST-01 with zero mocks
    {
        PriceValidationInput in;
        in.claimedPrice = 1.25;        // inside [min,max] band below
        in.escrowAmount = 0;           // SET PER TEST from CalculateCostMinions (see note)
        in.dagTimestamp = kEpochBase;
        in.blockSize    = 1'000'000;
        in.now          = kEpochBase + std::chrono::seconds( 5 );
        in.stats        = { 3, 1.20, 1.30 };  // count, min, max
        return in;
    }
}
// NOTE: for Accepted/CostMismatch cases compute escrowAmount ONCE in the fixture via
// TokenAmount::CalculateCostMinions(blockSize, claimedPrice) (EXPECT_OUTCOME_TRUE from
// test/testutil/outcome.hpp) rather than hard-coding a minions literal — the oracle owns the number.
TEST( PriceValidator, InBandAccepted )          { /* BaseInput → Accepted */ }
TEST( PriceValidator, AboveBandRejected )       { in.claimedPrice = 1.60; /* AboveBand */ }
TEST( PriceValidator, BelowBandRejected )       { in.claimedPrice = 0.90; in.escrowAmount = recomputed; /* BelowBand or CostMismatch per chain */ }
TEST( PriceValidator, FutureTimestampRejected ) { in.dagTimestamp = in.now + std::chrono::seconds( 31 ); }
TEST( PriceValidator, StaleTimestampRejected )  { in.dagTimestamp = in.now - std::chrono::seconds( 601 ); }
TEST( PriceValidator, CostMismatchRejected )    { in.escrowAmount = correct - 1; }
TEST( PriceValidator, NoCoverageRejected )      { in.stats = { 0, 0.0, 0.0 }; }
TEST( PriceValidator, LegacyNoPriceRejected )   { in.claimedPrice = 0.0; }
TEST( PriceValidator, BandBoundaryInclusive )   { in.claimedPrice = 1.30 * 1.10; /* == bandHigh → Accepted (Pitfall 4) */ }
TEST( PriceValidator, NaNRejectedDeterministically ) { in.claimedPrice = std::numeric_limits<double>::quiet_NaN(); /* CostMismatch, never UB */ }
```

### Build & run commands (Phase 06 verified precedent)

```powershell
# Source: 06-02-PLAN.md:84 — exact working invocation from Phase 6.
cmake --build SuperGenius\build\Windows\Release --config Release --target price_validator_test
SuperGenius\build\Windows\Release\test_bin\Release\price_validator_test.exe --gtest_filter=PriceValidator.*
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Trust poster's claimed price / single-point compare | Min/max-over-observed-window with tolerance band, escrow-anchored reference time | This milestone (D-01, D-06-02) | Validator never depends on poster-supplied time or price |
| `price_timestamp` wire field (REQUIREMENTS v1.0 wording) | Escrow DAG timestamp as reference (D-06-02/03) | Phase 6 | No new wire field to validate; `escrow_path` plumbing is Phase 8's job |
| Float price on wire | `double claimed_price` (proto field 6) with comment "double, never float: Phase 7 re-checks CalculateCostMinions(size, claimed_price) == escrow" | Phase 6 [VERIFIED: SGProcessing.proto:13-23] | Cost binding is exact integer equality — no epsilon anywhere |

**Deprecated/outdated:** none in-repo relevant to this phase.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | NaN comparisons are false and `static_cast<uint64_t>(NaN)` is UB/platform-dependent (IEEE-754 / C++ semantics — training knowledge; the FromDouble guard text is verified, the semantics claim is not tool-verified) | Pitfall 1 | Low: guard added regardless; if NaN were somehow rejected later in the chain the explicit check is still correct and cheaper |
| A2 | `-0.0 == 0.0` is true, so negative-zero claimed_price lands in `LegacyNoPrice` | phase_requirements VAL-04, Pitfall 1 | Trivial: worst case -0.0 takes CostMismatch path — still a deterministic reject |
| A3 | Boundary-inclusive recommendations (`T == now+skew` accepted, `T == now−maxAge` accepted, band edges inclusive) — recommendations, not locked | Pitfall 4 | Medium: Phase 8 convergence needs every honest node using the SAME boundary convention; tests lock whichever is chosen |
| A4 | `static` coinprices archive + unreferenced-member semantics keep `price_manager_test` link-clean after `PriceValidator.cpp` joins the target — reasoning from verified `BUILD_SHARED_LIBS OFF` + standard static-archive behavior, not from an actual link run | Pitfall 5 | Low-medium: if a shared-lib config is ever enabled, coinprices gains an undefined TokenAmount symbol; mitigation is a one-line plan verification step (build price_manager_test after the change) |
| A5 | The `Reason` mapping for non-finite/negative prices is `CostMismatch` (enum locked; mapping is a recommendation) | Pitfall 1 | Low: any deterministic mapping satisfies VAL-01; Phase 8 telemetry just needs the documented bucket |
| A6 | Window knob = TTL component (default `kStaleMaxAge`), `from = T − (ttl + skew)` | Pitfall 3 / Open Q2 | Medium: 30s disagreement between caller window and test expectations if planner picks the other reading; Pattern 4 helper contains the blast radius |

## Open Questions

1. **Where does `now` enter the pure validator?** (D-07-12's field list omits it, but D-07-03's max-age is "relative to when the validator runs" and D-07-11's timestamp checks need a reference.)
   - What we know: validator must be pure and hermetic (TEST-01 "no mocks"); price_manager_test's kEpochBase pattern injects all times.
   - What's unclear: struct field vs second function parameter.
   - Recommendation: **field in `PriceValidationInput`** (single-struct call signature, matches D-07-10's shape intent; diagnostics can echo it). Planner treats this as a small extension of the locked input struct, documented in the plan.
2. **"Window width" knob semantics** (D-07-04 names the knob; D-07-02 gives the formula `T − (ttl + skew)`).
   - What we know: TTL component defaults to `kStaleMaxAge` = 300s; skew = 30s; total lookback 330s.
   - What's unclear: does the env knob set the TTL component (300 default) or total lookback (330 default)?
   - Recommendation: knob sets the **TTL component** (name it e.g. `SGNS_PRICEVAL_WINDOW_TTL_S`, default 300) so the default reads as "quote TTL" — one constant reused from `PriceFreshness.hpp`, no near-duplicate 330.
3. **Which test target hosts TEST-01?** (Agent's discretion.)
   - What we know: `account_management_test` already links `genius_node_test` (Phase 6 wire tests live there) [VERIFIED: test/src/account/CMakeLists.txt:35-39]; a fresh `price_validator_test` follows the `price_*` suite convention and isolates the new suite; either link pulls `TokenAmount.o`.
   - Recommendation: **new `price_validator_test`** under `test/src/price_validator/` (matches the coinprices-domain suite family, keeps account test binary untouched, faster single-target builds). Link: `coinprices` + `genius_node_test` + `${AsyncIOManager_INCLUDE_DIR}` include (price_manager precedent).
4. **Self-heal helper placement** (D-07-06; agent's discretion): small free function beside the validator (e.g., `ShouldSelfHealFetch(reason) -> bool` or a documented note) vs purely inline in the Phase 8 caller.
   - Recommendation: land a trivial `bool ShouldTriggerRefetch(PriceValidationReason)` beside the validator now (testable, documents the policy), leaving the actual `GetQuotes` call to Phase 8.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| CMake + VS generator | building `price_validator_test` | ✓ | 3.29.2 (Strawberry), generator "Visual Studio 17 2022" [VERIFIED: cmake --version; CMakeCache.txt] | — |
| Configured build tree `SuperGenius\build\Windows\Release` | incremental target builds | ✓ | exists [VERIFIED: Test-Path] | — |
| GTest/gmock (vendored, via `addtest`) | TEST-01 | ✓ | wired by `addtest()` [VERIFIED: cmake/functions.cmake:16-18] | — |
| git | commit_docs | ✓ | present [VERIFIED: Get-Command] | — |
| Web/docs providers (Context7, exa, etc.) | external domain research | ✗ | — | Not needed: all phase knowledge is in-repo and was read directly; seam routed 2 questions to context7 but no context7 MCP tools are available in this session — every claim below is codebase-verified or explicitly tagged [ASSUMED] |

**Missing dependencies with no fallback:** none.
**Missing dependencies with fallback:** external docs lookups (see table) — resolved via direct source reads this session.

## Validation Architecture

SKIPPED — `workflow.nyquist_validation` is explicitly `false` in `.planning/config.json`. (TEST-01 still mandates the hermetic unit suite; its mechanics are fully specified in Code Examples above.)

## Security Domain

ASVS Level 1 (config `security_asvs_level: 1`, `security_enforcement: true`, block on `high`). This phase ADDS a validation control; it introduces no new attack surface (no network, no parsing, no secrets).

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|------------------|
| V2 Authentication | no | no auth surfaces in a pure function |
| V3 Session Management | no | none |
| V4 Access Control | indirectly | the validator IS the price-gaming access control (fail-closed by design: D-07-05/D-07-08); enforced at Phase 8 hook |
| V5 Input Validation | yes | this phase's whole subject: never trust wire `claimed_price` (NaN/negative/zero guards, Pitfall 1), escrow amount, or DAG timestamp; fail-closed defaults; env-parsed config validated (tolerance must be finite and ≥ 0 — clamp or reject nonsense env values rather than propagate NaN into band math) |
| V6 Cryptography | no | no crypto; escrow/DAG authenticity is existing consensus machinery (D-06-03 caveat: "DAG timestamp is poster-set; its trustworthiness is whatever consensus already enforces") |

### Known Threat Patterns for {pure C++ validator over untrusted wire data}

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Gamed price claim (high → drain escrow value; low → underpay) | Tampering | tolerance band over own observations (D-01/D-07-01); typed AboveBand/BelowBand |
| Honest price + lowered escrow | Tampering | cost binding: `CalculateCostMinions(size, claimed) == escrow_amount` (D-02), exact integer equality |
| Cherry-picked old favourable timestamp | Tampering | max-age 10 min + future-skew 30 s (D-03/D-07-03) |
| NaN/±inf/negative doubles to poison arithmetic or split consensus | Tampering/DoS | explicit `std::isfinite` + sign guard before the oracle (Pitfall 1); no UB in the verdict path |
| Missing-field legacy messages bypassing validation | Elevation of privilege | fail-closed `LegacyNoPrice` reject, hard cutover (D-07-08/D-07-09) |
| Verdict divergence across nodes (consensus split / DoS) | DoS | purity + injected `now`, one shared window formula, integer-equality cost check, locked reason taxonomy |

## Sources

### Primary (HIGH confidence — all read directly this session)
- `SuperGenius/src/coinprices/LocalPriceManager.hpp` — `PriceHistoryStats` (lines 59-66), `QueryHistory` inclusive-bounds + count==0 semantics (lines 126-135), `PriceObservation`, injectable `Clock`
- `SuperGenius/src/coinprices/PriceFreshness.hpp` — `kFreshMaxAge{60}`/`kStaleMaxAge{300}` (lines 9-10), closed-on-fresh-side boundary convention (lines 19-21)
- `SuperGenius/src/account/TokenAmount.hpp` — `CalculateCostMinions(uint64_t,double)` decl (lines 105-114), `PRECISION = 6`, `PRICE_PER_FLOP = 500`, `FLOPS_PER_BYTE = 20`, `MIN_MINION_UNITS = 1`
- `SuperGenius/src/account/TokenAmount.cpp` — `MIN_MINION_UNITS` floor + `value_too_large` failure (lines 65-107)
- `SuperGenius/src/base/ScaledInteger.cpp` — `FromDouble` guard (verbatim in Pitfall 1)
- `SuperGenius/src/processing/proto/SGProcessing.proto` — `Task.claimed_price` double field 6 + validation-contract comment (lines 13-23)
- `SuperGenius/src/account/proto/SGTransaction.proto` — `DAGStruct.timestamp` int64 field 5 (line 11), `EscrowTx{dag_struct=1, utxo_params=2, amount=3}` (lines 120-125)
- `SuperGenius/src/account/GeniusNode.cpp` — `ProcessImage` stamping (lines 2683-2725), `GetProcessCost` (lines 2816-2847)
- `SuperGenius/src/account/CMakeLists.txt` — `TokenAmount.cpp` in `GENIUS_NODE_SOURCES` (line 84), `genius_node_objs`/`genius_node`/`genius_node_test` (lines 91-105), `SGNS_CONSOLE_LOG_TESTS` precedent
- `SuperGenius/src/CMakeLists.txt` — `GENIUS_NODE_LIBS` includes `coinprices` (lines 4-45)
- `SuperGenius/src/coinprices/CMakeLists.txt` — coinprices sources/links
- `SuperGenius/cmake/functions.cmake` — `addtest()` behavior (lines 8-45)
- `SuperGenius/test/src/price_manager/CMakeLists.txt` + `price_manager_test.cpp` — suite link pattern, kEpochBase hermetic pattern (lines 30-35)
- `SuperGenius/test/src/account/CMakeLists.txt` — `account_management_test` links `genius_node_test` + `/WHOLEARCHIVE` precedent (lines 35-61)
- `SuperGenius/test/testutil/outcome.hpp` — `EXPECT_OUTCOME_TRUE/FALSE` macros
- `SuperGenius/src/coinprices/PriceEndpoints.hpp` — env-var resolution precedent, no-static rule
- `SuperGenius/build/CommonCompilerOptions.cmake` — C++17 (lines 6-7); `SuperGenius/build/Windows/Release/CMakeCache.txt` — VS 17 2022 generator
- `.planning/workstreams/tokenprice/` — REQUIREMENTS.md (v1.1), STATE.md (Phase 6 decisions), 07-CONTEXT.md (D-07-01..12), 06-CONTEXT.md (D-06-02/03/05/06/07), 06-02-PLAN.md (build command, line 84)
- `SuperGenius/CLAUDE.md` — architecture constraints (one owning module, never duplicate logic, refactor-first)

### Secondary (MEDIUM confidence)
- None — no external doc claims were needed; nothing sourced from web this session.

### Tertiary (LOW confidence)
- IEEE-754 NaN semantics and UB claims tagged `[ASSUMED]` in the Assumptions Log (A1, A2) — training knowledge; the relevant guard code they concern is verified verbatim.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — every component read from source this session; zero external packages
- Architecture: HIGH — pure-function shape, check order, config mechanism, and build wiring all anchored to verified in-repo precedents; two open questions (Q1 `now`, Q2 window knob) carry explicit recommendations
- Pitfalls: HIGH — five of seven pitfalls grounded in verbatim source; NaN-semantics claim honestly tagged [ASSUMED] with a code-level mitigation that is safe either way

**Research date:** 2026-10-06
**Valid until:** indefinite (in-repo facts; re-verify Pitfall 5 if `BUILD_SHARED_LIBS` is ever enabled or `TokenAmount.cpp` moves targets)
