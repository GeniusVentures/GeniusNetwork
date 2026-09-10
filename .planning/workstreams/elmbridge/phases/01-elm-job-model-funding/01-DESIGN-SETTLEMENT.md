# 01-DESIGN-SETTLEMENT: ELM Settlement / Refund / Terminal-State Semantics

**Phase 1 design deliverable (FUND-03, D-01/D-02/D-03, OD-3).** Phase 1 ships this design + the rate record (plan 01-02 `CreateElmRateRecordCRDTTransaction`) + `ElmClocks` derivation only. Measurement stamps land in Phase 3 (envelope schema); payout rework + wiring land in Phase 4. Nothing here changes Phase 1/2 code.

---

## 1. Measurement: per-subtask wall-clock windows (D-01)

**What is measured:** each subtask's grab→publication interval, worker-attested, carried in the result envelope artifact — schema fields, zero proto change.

| Stamp | Written at | Anchor |
|---|---|---|
| `grab_time_usec` | `ProcessingEngine::ProcessSubTask` entry, before any fetch | `src/processing/processing_engine.cpp` ProcessSubTask |
| `finish_time_usec` | `CompleteSubTask` publication (envelope assembled) | `src/processing/processing_engine.cpp` CompleteSubTask |

**Model download is included by construction**: the grab stamp precedes the model/input fetch (`fetchOutputData` path, `processing_subtask_queue_accessor_impl.cpp:379-411`), so a worker that spends 20min downloading a 4GB model bills that time. This is deliberate: the requestor declared `maximum_processing_hours` for the *job*; the worker's clock risk is bounded by the deadline (D-03) and the escrow cap.

**Read path at settlement:** the finalizing node already fetches every result envelope via the `fetchOutputData` lambda (`FinalizeQueueProcessing`, `processing_subtask_queue_accessor_impl.cpp:379-411`); the stamps are read from those fetched artifacts. No new transport.

**Accepted residual (T-01-10):** stamps are worker-attested. A worker *under*-reporting hurts only itself; *over*-reporting is capped at the escrow max (D-03). v1.0 single-node accepts this; multi-node v2 revisits with attested timestamps.

## 2. Billing: sum of measured windows, milli-hour truncation (D-01/D-02)

```
window_i_ms        = finish_time_usec_i - grab_time_usec_i          (clamped >= 0)
window_millihours  = llround(window_i_ms / 3600000.0 * 1000.0)      // window in milli-hours
billable_millihours= Σ_i window_millihours_i                        // D-01: sum of windows
billable_minions   = billable_millihours * 3 / 10                   // D-02 integer path (see below)
billable_minions   = min(billable_minions, escrow_max_minions)      // D-03 cap
```

- The `* 3 / 10` is the identical integer path as `sgns::processing::ElmEscrowMinions` (`src/processing/processing_clocks_elm.cpp`, plan 01-02): `$0.0003/h × 10^6 minions/$ at kUsdPerGnusRate=1.0`, milli-hour → llround first (never bare truncation), final integer division floors (requestor-favorable, D-02).
- **Cap semantics:** if `billable > escrow_max`, the requestor pays exactly the escrow max; over-max windows refund nothing extra (worker carries overrun risk past its declared deadline — mirrors the lock expiry at `deadline+grace`).

## 3. Payout rework in `BuildPayoutOutputs` — ELM branch only (OD-3)

**Anchor:** `src/account/TransactionManager.cpp:1104-1202` (`BuildPayoutOutputs`), called from `PayEscrow` at `:1205-1277` (payout construction `:1253-1257`).

Phase 4 adds an ELM branch alongside the existing per-subtask even split:

1. **Billable pool:** peers+developer paid from `billable_minions` (§2), not the full escrow.
2. **Split rule (OD-3, supersedes even-split for ELM):** each work item's share is **proportional to its measured window**:
   ```
   share_i = billable_minions * window_millihours_i / billable_millihours   (uint128, floor)
   remainder distributed to the largest-window items (deterministic tiebreak: lexicographic subtaskid)
   ```
   Rationale: a 90-minute generation and a 30-second one split the bill 180:1, not 1:1 — even-split would systematically underpay the long-generation worker.
3. **Malformed-entry filter (unchanged):** one malformed envelope never blocks payout — honest entries paid, bad entry gets nothing (`BuildPayoutOutputs:1122-1131` precedent).
4. **Refund output:** `(escrow_max_minions − billable_minions)` returns as an explicit output to `escrow_tx->GetSrcAddress()` (the escrow source; same address `PayEscrow` already uses for the CRDT topic at `:1249-1252`).
5. **Conservation check preserved:** Σ(outputs) == escrow_amount, uint128 (`:1191-1200` total check stays; refund output makes it hold when billable < escrow).

**Rate at settlement:** read the `elm_rate` sibling CRDT key (written by plan 01-02's `CreateElmRateRecordCRDTTransaction` — `usd_per_hour`, `usd_per_gnus`, `minions`, `maximum_processing_hours`) and/or the task-JSON funding block; the two agree by construction since both derive from the same constants.

## 4. Terminal states: published envelope, never a silent re-grab (SC-4, F9)

**Problem (research F9):** today an over-time subtask hits the lock-expiry path (`processing_subtask_queue.cpp:166-196`), the item unlocks, and peers re-grab — an infinite burn loop with no terminal record.

**Design:** over-time/cancelled subtasks publish a **success-shaped result envelope** that `ValidateIndividualResult` structurally accepts:

```
{ artifact_uri            // real or empty-marker artifact
, chunk_hash              // the subtask's notional chunk hash (1:1 mapping doc)
, payout_metadata         // zero-value worker share, finish_reason recorded
, finish_reason           // "cancelled" | "error" | "budget_exceeded"
, grab_time_usec          // measurement stamps still present
, finish_time_usec        //   (== deadline for cancelled; == failure detect for error)
}
```

- `ValidateIndividualResult`'s six structural checks (artifact URI + chunk hash + payout metadata present, subtaskid keying — `processing_validation_core.cpp:47-186`) pass by construction; the subtask marks processed; the queue drains; **no re-grab**.
- `BUDGET_EXCEEDED` rides this **success-shaped path as a published envelope** — it is a *terminal, billable-to-cap* state (requestor pays the declared max per §2 cap), never a silent loop.
- Cancellation fires at the per-subtask deadline (D-03/D-10) via the Phase 3 cancel mechanism (MNN `USER_CANCEL` patch lands Phase 3 per D-002); the derived lock (plan 01-03 Task 1) already bounds the re-grab window until then.

## 5. Phase boundaries (explicit)

| Piece | Phase |
|---|---|
| `ElmClocks`/`ElmEscrowMinions` derivation, `elm_rate` CRDT record | **1** (shipped: plans 01-02) |
| Envelope schema fields `grab_time_usec`/`finish_time_usec`, cancel mechanism | **3** |
| `BuildPayoutOutputs` ELM branch, refund output, `PayEscrow` wiring, terminal-envelope publication | **4** |
| This design document | **1** (this file) |
