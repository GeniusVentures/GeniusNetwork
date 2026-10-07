# Milestones

## v1.1 v1.1 (Shipped: 2026-10-07)

**Phases completed:** 3 phases, 7 plans, 17 tasks

**Key accomplishments:**
- Bounded, timestamped, strand-confined genius-ai price history in LocalPriceManager with inclusive-window min/max/count queries and documented empty-after-restart degradation — no mutexes, no call-site churn.
- Task.claimed_price (double, proto field 6) stamped by ProcessImage from the single GetQuotes read that sized the escrow, with all callers migrated to the ProcessCost struct.
- Escrow price gate wired into ValidateTransactionForConsensus (Pending on missing task / typed Reject) plus a GrabTask claim-time backstop, with all price evidence assembled node-locally in GeniusNode behind injected seams — honest 3-node flow green 9/9 runs with enforcement live.
- Published the typed rejection-release consensus subject (sgns.task_rejection.v1) end-to-end — proto message, constant, Create/Decode helpers, forged-subject CheckSubject branch, and routing at all three dispatch sites — the one-way D-08-06 contract that authorizes CONS-02 rejection refunds.
- Made the rejection subject live end-to-end: vote-time independent re-verification (Approve only when the recomputed gate reason matches), certified rejections restore the poster's funds through FAILED-rollback (regime 1) or a CONFIRMED-gated full-refund no-burn release spend (regime 2), and the first honest rejector proposes the subject the instant the gate Rejects.
- Proved Phase 8 end-to-end in the 3-node loopback topology: a gamed-price job posted through the real ProcessImage wire path is BelowBand-rejected by both honest validators (reason=6), never processed, and refunded to the poster to exact uint64 equality via the regime-1 FAILED rollback — while the honest PostProcessing case stays green in the same suite with all enforcement live.

---
