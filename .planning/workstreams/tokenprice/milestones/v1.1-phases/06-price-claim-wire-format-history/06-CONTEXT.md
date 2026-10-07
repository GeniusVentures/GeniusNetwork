# Phase 6: Price Claim Wire Format & History - Context

**Gathered:** 2026-10-05
**Status:** Ready for planning

<domain>
## Phase Boundary

Every posted job carries a verifiable price claim, and every node keeps a bounded local record of prices it observed. Requirements: WIRE-01, WIRE-02, HIST-01, HIST-02. Validation logic (Phase 7) and consensus hook (Phase 8) are out of scope.
</domain>

<decisions>
## Implementation Decisions

- **D-06-01 Quote plumbing:** `GetProcessCost` returns a struct `{minions, PriceQuote}` so `ProcessImage` stamps price from the same quote that sized the escrow (single read, WIRE-02). `GetGNUSPrice`/`GetCoinprice` keep their `double` API as thin wrappers; no SDK/wallet-facing break.
- **D-06-02 Wire fields:** `SGProcessing::Task` gains ONLY a claimed price (`double`, USD per genius-ai, new field number 6). No separate timestamp field: the escrow transaction already carries the escrowed amount (`EscrowTx.amount`) and a DAG timestamp (`DAGStruct.timestamp`), reachable via `task.escrow_path`. This supersedes the "price_timestamp" wording in REQUIREMENTS.md D-01/WIRE-01 and ROADMAP criterion 2.
- **D-06-03 Time basis for validation:** the validator's reference time is the escrow DAG timestamp. Because a quote may be served from cache, the observation window must look back by quote TTL plus clock skew (consumed in Phase 7). Caveat: DAG timestamp is poster-set; its trustworthiness is whatever consensus already enforces.
- **D-06-04 Cost binding input:** validity of the escrowed amount = `CalculateCostMinions(blockSize, claimed_price) == escrow amount` (Phase 7).
- **D-06-05 History contents:** `LocalPriceManager` records every `genius-ai` quote actually fetched from a network tier (CoinGecko / GnusPriceService); NOT L1 cache hits. Bounded ring buffer, configurable retention (default about 24h, plus a count cap). Queries: min/max/count over a time window.
- **D-06-06 Restart:** in-memory only; empty after restart. Phase 7's no-coverage policy handles the empty case (HIST-02 = documented safe degradation).
- **D-06-07 Role of history:** local evidence for a node's own accept/reject input only (D-04 independence). It is not a validity ruling.

### Agent's Discretion
Struct/field names, ring buffer data structure, locking model (follow the manager's existing strand), config key names.
</decisions>

<canonical_refs>
## Canonical References

- `.planning/workstreams/tokenprice/REQUIREMENTS.md`, `ROADMAP.md`
- `SuperGenius/src/account/GeniusNode.cpp` (`ProcessImage`, `GetProcessCost`, `GetGNUSPrice`)
- `SuperGenius/src/coinprices/LocalPriceManager.{hpp,cpp}`, `PriceQuote.hpp`
- `SuperGenius/src/processing/proto/SGProcessing.proto` (Task fields 1-5 used)
- `SuperGenius/src/account/proto/SGTransaction.proto` (`EscrowTx`, `DAGStruct.timestamp`), `EscrowTransaction.hpp`
</canonical_refs>

<deferred>
## Deferred Ideas

- Trust/reputation value for posters and penalties for repeat bad actors, applied by consensus (new capability; candidate for a later milestone).
- Open questions still for Phase 7/8: tolerance and window defaults, legacy-task policy, exact consensus hook point.
</deferred>
