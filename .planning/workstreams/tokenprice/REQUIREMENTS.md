# Requirements: Job Price Validation (v1.1)

**Defined:** 2026-10-05
**Workstream:** tokenprice
**Branch:** SuperGenius `dev_price_validation` (from `dev_tokenprice`)
**Core Value:** A job poster cannot game the system by claiming a GNUS price that differs from the real market price. `GeniusNode::ProcessImage` prices a job from `GetGNUSPrice`; every node that receives the task over CRDT/graphsync independently verifies the claimed price against its own timestamped price observations, and consensus accepts or rejects the job.

**Anchors:** `GeniusNode::ProcessImage` / `GetProcessCost` / `GetGNUSPrice` (`src/account/GeniusNode.cpp`), `LocalPriceManager` + `PriceQuote` (`src/coinprices/`), `SGProcessing::Task` (`src/processing/proto/SGProcessing.proto`), `HoldEscrow` / `ParseEscrowTransaction` (`src/transaction/TransactionManager.cpp`), `TokenAmount::CalculateCostMinions`.

## Design Decisions (locked unless revisited)

- **D-01 Anti-gaming method:** the job carries `claimed_price` and `price_timestamp` (the `PriceQuote` fetch time). A validator accepts only if (a) `price_timestamp` is plausible relative to the job post time, and (b) the claimed price lies within the **[min, max] of the validator's own observed prices in a window around `price_timestamp`, widened by a tolerance percentage**. Min/max-with-tolerance is used rather than a single point because validators fetch at different moments and the market moves.
- **D-02 Cost binding:** validators recompute `CalculateCostMinions(blockSize, claimed_price)` and require it to equal the escrowed amount, so a poster cannot pair an honest price with a lowered escrow.
- **D-03 Timestamp bound:** `price_timestamp` must not be in the future (beyond clock skew) and not older than a max age relative to the job post time, so a poster cannot cherry-pick an old favourable price.
- **D-04 Independence:** validators use only their own `LocalPriceManager` observations, never the poster's data.

## v1.1 Requirements

### Wire Format (WIRE)

- [ ] **WIRE-01**: `SGProcessing::Task` gains backward-compatible fields for the claimed GNUS price and the price timestamp; existing builds and stored tasks still parse
- [ ] **WIRE-02**: `ProcessImage` stamps the price and timestamp from the same `PriceQuote` that produced the escrowed cost (single read, no second fetch)

### Price History (HIST)

- [ ] **HIST-01**: `LocalPriceManager` retains a bounded, timestamped history of fetched `genius-ai` quotes (ring buffer, configurable retention) with min/max-over-window queries
- [ ] **HIST-02**: History survives restart or degrades safely (documented behavior when empty after startup)

### Validation Engine (VAL)

- [ ] **VAL-01**: Pure validator function: timestamp sanity (D-03), tolerance-band check against observed window (D-01), and cost-binding check (D-02), returning accept/reject with a typed reason
- [ ] **VAL-02**: Tolerance %, window width, max age and clock skew are configurable with documented defaults
- [ ] **VAL-03**: Insufficient-coverage policy when the validator has no observations near `price_timestamp` (fetch current and widen, or defer) is defined and tested
- [ ] **VAL-04**: Legacy tasks without the new fields have a defined policy (reject after a grace flag, or accept with warning)

### Consensus Integration (CONS)

- [ ] **CONS-01**: A node receiving a task over CRDT/graphsync runs the validator before processing; rejected tasks are not processed
- [ ] **CONS-02**: Acceptance/rejection is deterministic enough that honest validators converge, and a rejected job's escrow is returned to the poster
- [ ] **CONS-03**: A poster who games the price (high or low) is rejected by honest validators

### Testing (TEST)

- [ ] **TEST-01**: Hermetic unit tests for the validator covering in-band, out-of-band (high and low), future/stale timestamp, cost mismatch, no-coverage and legacy cases
- [ ] **TEST-02**: Multi-node integration test: honest job accepted, gamed-price job rejected, using the loopback stub price source

## Open Questions (resolve during phase discussion)

1. Where exactly does "consensus accepts or rejects" hook in: at task enqueue/receive in the processing queue, at escrow transaction validation, or both?
2. Default tolerance (e.g. 5%?) and window (e.g. 10 min?) — to be derived from GNUS price volatility data.
3. Legacy-task policy and rollout (version gate?).

## Out of Scope

- On-chain price oracle (SRC-01 stays deferred)
- Changing the pricing formula itself
- token.gnus.ai Worker changes

## Traceability

| Requirement | Phase |
|-------------|-------|
| WIRE-01, WIRE-02, HIST-01, HIST-02 | Phase 6 |
| VAL-01, VAL-02, VAL-03, VAL-04, TEST-01 | Phase 7 |
| CONS-01, CONS-02, CONS-03, TEST-02 | Phase 8 |
