# Phase 7: Price Validator - Context

**Gathered:** 2026-10-06
**Status:** Ready for planning

<domain>
## Phase Boundary

A deterministic, **pure** price validator as a standalone unit: timestamp sanity (D-03), tolerance-band check over the node's own observed window (D-01), and escrow cost binding (D-02) — returning accept/reject with a typed reason plus diagnostics. Plus its configuration (VAL-02), insufficient-coverage policy (VAL-03), legacy-task policy (VAL-04), and hermetic unit tests (TEST-01).

Requirements in scope: VAL-01, VAL-02, VAL-03, VAL-04, TEST-01.

**Not in this phase:** wiring the validator into the task receive/consensus path (Phase 8), escrow refund behavior (Phase 8), multi-node integration testing (Phase 8, TEST-02), any wire/proto changes (Phase 6 shipped the wire format), changes to the pricing formula, and any Worker (token.gnus.ai) changes.
</domain>

<decisions>
## Implementation Decisions

### Threshold defaults & configuration
- **D-07-01 Tolerance:** default **10%** — each node widens its observed window `[min, max]` by ±10%. Chosen over 5% (OQ2's tentative value) because genius-ai is a volatile low-cap token and the tolerance only needs to absorb cross-node fetch-moment variance, not intra-window market movement; 10% still catches deliberate gaming. — **Reversibility:** reversible — a constant in `PriceValidatorConfig`.
- **D-07-02 Window:** **asymmetric `[T − (quote TTL + skew), T + skew]`** around the escrow DAG timestamp T, where quote TTL = `kStaleMaxAge` (300s) from `PriceFreshness.hpp`. Exactly D-06-03: minimal dead band, smallest cherry-picking surface. Not the symmetric ±10 min suggested in OQ2 — prices *after* T could not have been used by the poster. — **Reversibility:** reversible.
- **D-07-03 Timestamp bounds:** clock skew allowance **30s** (within one freshness band), max age **10 min** relative to when the validator runs. A 10-min-old escrow is beyond any quote TTL, so an honest poster's T always passes the age check. — **Reversibility:** reversible.
- **D-07-04 Configuration:** `PriceValidatorConfig` plain struct with code defaults, overridable via **`SGNS_PRICEVAL_*` environment variables** — matching the Phase 4 env-var precedent (`SGNS_CONSOLE_LOG_TESTS`/`SGNS_DEBUGLOGS`, Phase 4 D-01). `GeniusNodeConfig` stays untouched (brace-initialized aggregate). All four knobs (tolerance, window width, skew, max age) documented with these defaults per VAL-02. — **Reversibility:** reversible.

### No-coverage policy (VAL-03)
- **D-07-05 Verdict:** `QueryHistory` returns `count == 0` over the window → **reject with `NO_COVERAGE`**. Deterministic and fail-closed; the typed reason distinguishes "unverifiable" from "gamed" for Phase 8 logging/telemetry. A node with no evidence does not vouch for a job. Fetch-and-widen was rejected because a fresh quote is not from time T and makes the verdict timing-dependent (breaks the determinism Phase 8 convergence needs); defer was rejected because it introduces a third state the consensus hook would have to handle.
- **D-07-06 Self-heal:** the *verdict* stands, but on `NO_COVERAGE` the node triggers a **background fetch** via `LocalPriceManager` so subsequent tasks regain coverage within one fetch cycle. The self-heal trigger is a caller-side side effect — the validator function itself stays pure (returns the verdict; the Phase 8 caller observes the reason and fetches).
- **D-07-07 Minimum coverage:** `count >= 1` is coverage. A single observation is still evidence; the market moving >10% within the 300s lookback is rare, and the alternative (requiring 2+) would make rarely-fetching nodes reject almost everything.

### Legacy-task policy (VAL-04)
- **D-07-08 Verdict:** `claimed_price == 0.0` (proto3 default, field absent) → **reject with `LEGACY_NO_PRICE`**. Fail-closed from day one: no grace flag to remove later, no window where gaming-via-missing-field is possible. — **Reversibility:** one-way — once Phase 8 enforces rejection network-wide, reverting to a grace/accept policy changes consensus-visible behavior for legacy messages.
- **D-07-09 Rollout:** **hard cutover**, no log-only shakedown period. The network is young; posters and validators ship together in the same SuperGenius node release, so stale posters are rare and self-inflicted. Simplicity beats migration machinery.

### Result shape & reason taxonomy (VAL-01)
- **D-07-10 Return type:** `struct { bool accepted; Reason reason; ...diagnostics }` — a typed enum (`Reason`) for control flow plus the computed band / observed stats carried in the struct, so Phase 8 logging and tests assert details without re-deriving them. Not `outcome::result` error codes (accept is the common case, not success-vs-error) and not enum-only (forces callers to recompute the band to log why). — **Reversibility:** costly — Phase 8 will consume this API; changing the shape after integration touches the consensus path.
- **D-07-11 Check order:** fixed fail-fast chain **legacy → timestamp sanity → cost binding → band**. Cheapest/most structural checks first; the first three need no history query at all; exactly one reason per input — deterministic and easy to test. Cost binding runs before the band check (an honest-price/lowered-escrow attack fails on cost binding with its specific reason).
- **D-07-12 Home & input:** **free function in `SuperGenius/src/coinprices/`** taking a `PriceValidationInput` struct: `claimed_price` (double), escrow amount (uint64), DAG timestamp, blockSize (uint64), and the already-aggregated `PriceHistoryStats{count, min, max}`. The caller (GeniusNode, Phase 8) performs the `QueryHistory` and escrow fetch. The validator depends on nothing but `TokenAmount` + the stats struct → hermetically testable with zero mocks. Reason enum values: `Accepted`, `LegacyNoPrice`, `TimestampFuture`, `TimestampStale`, `CostMismatch`, `AboveBand`, `BelowBand`, `NoCoverage`. — **Reversibility:** reversible (file placement) / costly (input struct after Phase 8 wiring).

### Agent's Discretion
Exact file names (e.g., `PriceValidator.hpp/.cpp` vs a header-only header), `Reason` enum spelling, diagnostics field set, env-var key names beyond the `SGNS_PRICEVAL_` prefix, test file organization under `test/src/coinprices/`, and whether the self-heal helper (D-07-06) lands as a small free function beside the validator or inline in the Phase 8 caller.

### Folded Todos
None folded.
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements & roadmap
- `.planning/workstreams/tokenprice/REQUIREMENTS.md` — D-01..D-04 design decisions, VAL/TEST requirements, open questions this context resolves
- `.planning/workstreams/tokenprice/ROADMAP.md` — Phase 7 goal and success criteria
- `.planning/workstreams/tokenprice/phases/06-price-claim-wire-format-history/06-CONTEXT.md` — D-06-01..D-06-07 decisions this phase consumes (escrow DAG timestamp as reference time, history semantics, cost-binding input)

### Wire & transaction format
- `SuperGenius/src/processing/proto/SGProcessing.proto` — `Task.claimed_price` (field 6) and its validation contract comment
- `SuperGenius/src/account/proto/SGTransaction.proto` — `EscrowTx{dag_struct, utxo_params, amount}` and `DAGStruct.timestamp` (int64, field 5)

### Price domain
- `SuperGenius/src/coinprices/LocalPriceManager.hpp` — `QueryHistory(from, to)` → `PriceHistoryStats{count, min, max}`; no-coverage = count==0, not an error; in-memory only
- `SuperGenius/src/coinprices/PriceFreshness.hpp` — `kFreshMaxAge` (60s) / `kStaleMaxAge` (300s) freshness bands (the quote TTL feeding the window width)
- `SuperGenius/src/account/TokenAmount.hpp` — `CalculateCostMinions(total_bytes, price_usd_per_genius) -> outcome::result<uint64_t>` (cost-binding check)

### Poster-side stamping (what the validator validates against)
- `SuperGenius/src/account/GeniusNode.cpp` — `ProcessImage` (~line 2694–2790: `GetProcessCost`, `task.set_claimed_price(cost.quote.price)`, `HoldEscrow`), `GetProcessCost` (~line 2816)
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `LocalPriceManager::QueryHistory` — the exact evidence input; already injectable-clock testable
- `PriceHistoryStats` / `PriceObservation` structs — reuse as the validator's evidence types rather than redefining
- `PriceFreshness.hpp` shared-constants pattern (`inline constexpr`) — the precedent for publishing validator defaults as named constants consumed by code and tests
- `TokenAmount::CalculateCostMinions` — the cost-binding oracle; `outcome::result` must be handled (a failure is a cost-mismatch reject, not a crash)
- `test/testutil/outcome.hpp` macros (`EXPECT_OUTCOME_*`) and the `test/src/coinprices/` suite layout from Phases 3/6

### Established Patterns
- Pure-function + injectable-clock hermetic testing (Phase 3/6 pattern: no network, no mocks beyond seams)
- Env-var-only runtime configuration with `SGNS_` prefixed names (Phase 4 D-01)
- Struct-return with embedded reason (cf. `PriceFetchFailure` status-bearing returns in `PriceFetchError.hpp`)

### Integration Points
- Phase 8 will call the validator from the task-receive path (`GeniusNode.cpp` ~line 3458 consumes `maybe_task.value().escrow_path()`); the escrow transaction is fetched via `TransactionManager::FetchTransaction(globaldb, escrow_path)` (see `PayEscrow`, `TransactionManager.cpp` ~line 1256) — that plumbing stays out of the pure validator but shapes `PriceValidationInput`
- Self-heal fetch goes through the existing `LocalPriceManager::GetQuotes({"genius-ai"})` seam
</code_context>

<specifics>
## Specific Ideas

- The band check math: accept iff `claimed_price ∈ [min·(1−tol), max·(1+tol)]` over the node's own window observations, with `tol = 10%` default.
- Timestamp sanity: reject `TimestampFuture` if `T > now + 30s`; reject `TimestampStale` if `T < now − 10min`.
- One deterministic reason per validation; tests should be able to construct each reason with a plain struct literal — no mocks anywhere in TEST-01.
</specifics>

<deferred>
## Deferred Ideas
- Trust/reputation for repeat bad-actor posters and consensus-applied penalties (carried from Phase 6; later milestone).
- Tolerance/window defaults derived from real GNUS volatility telemetry (revisit D-07-01/02 defaults once mainnet data exists; config knobs make this tunable without code change).

### Reviewed Todos (not folded)
- "Fix Vulkan capability-probe deadlock/crash in ProcessingManager::Create path" — keyword-only match ("validator"), unrelated domain (Vulkan/ProcessingManager); remains an open testing todo in its own right.
</deferred>

---
*Phase: 7-Price Validator*
*Context gathered: 2026-10-06*
