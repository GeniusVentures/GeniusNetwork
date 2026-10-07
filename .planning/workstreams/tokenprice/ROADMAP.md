# Roadmap: Job Price Validation (v1.1)

**Workstream:** tokenprice
**Status:** PLANNING
**Phases:** 6-8
**Previous milestone:** v1.0 PriceCoordinator (shipped 2026-10-05, archived: `.planning/milestones/tokenprice-v1.0-ROADMAP.md`)

## Overview

Close the price-gaming hole. Phase 6 gives jobs a verifiable price claim (wire fields stamped from the exact `PriceQuote` used) and gives each node a timestamped price history to check claims against. Phase 7 builds the validator as a pure, hermetically tested unit: timestamp sanity, tolerance band over the node's own observed window, and escrow cost binding. Phase 8 hooks the validator into the receive path so consensus accepts or rejects jobs, returns escrow on rejection, and proves it with a multi-node test.

## Phases

- [x] **Phase 6: Price Claim Wire Format & History** — Task `claimed_price` proto field, `ProcessImage` stamping, `LocalPriceManager` timestamped history with window min/max (completed 2026-10-05)
- [x] **Phase 7: Price Validator** — pure validator (timestamp, tolerance band, cost binding), config, coverage and legacy policies, hermetic tests (completed 2026-10-06)
- [x] **Phase 8: Consensus Integration** — validate on task receive, reject and refund escrow, multi-node gamed-price test (completed 2026-10-06)

## Phase Details

### Phase 6: Price Claim Wire Format & History

**Goal**: Every posted job carries a verifiable price claim and every node can answer "what prices did I observe around time T?"
**Requirements**: WIRE-01, WIRE-02, HIST-01, HIST-02
**Success Criteria**:
  1. Old and new `Task` messages round-trip; builds without the fields still parse
  2. `ProcessImage` stamps the claimed price from the same quote that sized the escrow (timestamp = escrow DAG timestamp)
  3. History returns min/max/count for a window, bounded by retention

**Plans**: 2/2 plans complete
Plans:
- [x] 06-01-PLAN.md — LocalPriceManager bounded timestamped genius-ai history + QueryHistory (HIST-01, HIST-02)
- [x] 06-02-PLAN.md — Task.claimed_price field + ProcessCost quote plumbing + ProcessImage stamping (WIRE-01, WIRE-02)

### Phase 7: Price Validator

**Goal**: A deterministic validator decides accept/reject with a typed reason
**Requirements**: VAL-01, VAL-02, VAL-03, VAL-04, TEST-01
**Success Criteria**:
  1. In-band accepted; high/low out-of-band rejected
  2. Future, stale, cost-mismatch and no-coverage cases behave per policy
  3. All thresholds configurable with documented defaults

**Plans**: 1/1 plans complete
Plans:
- [x] 07-01-PLAN.md — pure `ValidatePrice` fail-fast chain (typed reasons, config + `SGNS_PRICEVAL_*` env, no-coverage/legacy policies) + hermetic `price_validator_test` (VAL-01..VAL-04, TEST-01)

### Phase 8: Consensus Integration

**Goal**: Receiving nodes enforce the validator and honest nodes converge
**Requirements**: CONS-01, CONS-02, CONS-03, TEST-02
**Success Criteria**:
  1. Gamed-price job is not processed by honest nodes and its escrow is returned
  2. Honest job is accepted by all honest nodes
  3. Multi-node loopback test green

**Plans**: 4/4 plans complete
Plans:
- [x] 08-01-PLAN.md — consensus price gate (ValidateTransactionForConsensus escrow branch, Pending-on-missing-task) + claim-time backstop in GrabTask, GeniusNode evidence wiring, task_queue_test unit cases (CONS-01, CONS-03)
- [x] 08-02-PLAN.md — TaskRejectionSubject consensus subject: proto message + sgns.task_rejection.v1 constant + Create/Decode + CheckSubject branch + dispatch switches, gated by one-way-publish decision checkpoint (CONS-02)
- [x] 08-03-PLAN.md — rejection-subject handlers (independent re-verification), first-rejector proposal trigger, poster refund regime 1 (FAILED rollback) + regime 2 (CONFIRMED-gated full-refund release) (CONS-02, CONS-03)
- [x] 08-04-PLAN.md — TEST-02: GamedPriceJobRejectedAndRefunded multi-node case (stub-flip construction, no-processing + exact-refund assertions) + full-suite honest-acceptance proof (CONS-01, CONS-02, CONS-03, TEST-02)

## Progress

| Phase | Plans | Status | Completed |
|-------|-------|--------|-----------|
| 6. Price Claim Wire Format & History | 0/0 | Complete    | 2026-10-05 |
| 7. Price Validator | 0/1 | Complete    | 2026-10-06 |
| 8. Consensus Integration | 4/4 | Complete | 2026-10-06 |
