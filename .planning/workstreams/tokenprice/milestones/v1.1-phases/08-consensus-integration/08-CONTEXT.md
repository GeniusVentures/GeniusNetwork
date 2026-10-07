# Phase 8: Consensus Integration - Context

**Gathered:** 2026-10-06
**Status:** Ready for planning

<domain>
## Phase Boundary

Wire the Phase 7 price validator into the receiving path so consensus accepts or rejects jobs: the escrow-transaction consensus gate cross-references the task's `claimed_price`, a rejected job's escrow is returned to the poster via a consensus-certified release, and the behavior is proved with a multi-node loopback test. Requirements: CONS-01, CONS-02, CONS-03, TEST-02.

**Not in this phase:** changes to the validator itself (Phase 7 shipped `ValidatePrice`/config/refetch hook), wire/proto task changes (Phase 6 shipped `claimed_price`), poster-side pricing changes beyond what the gate requires, penalties/reputation for repeat offenders, on-chain price oracle, pricing formula, Worker (token.gnus.ai) changes.
</domain>

<decisions>
## Implementation Decisions

### Enforcement hook point (CONS-01)
- **D-08-01 Gate location:** enforcement lives in the **existing consensus transaction-validation path** — extend `TransactionConsensusHandler::ValidateTransactionForConsensus` (escrow transactions, via the `ParseEscrowTransaction` dispatch context) to cross-reference the claiming task's `claimed_price` and run `ValidatePrice`. Explicit user direction: "run it at CRDT sync… we have existing consensus mechanisms in place, maybe in TransactionManager — follow that." Not a GlobalDB new-element callback. — **Reversibility:** costly — touches the shared consensus validation chain every transaction passes through.
- **D-08-02 Missing-task ordering:** the poster commits escrow *before* the task element (two CRDT transactions). When the escrow arrives without its task record, the gate returns **`Pending()`** (existing migration-allowlist precedent in `TransactionConsensusHandler.cpp` ~line 485) — never reject on absence. Deterministic convergence preserved. — **Reversibility:** reversible.
- **D-08-03 Reject semantics:** a Reject verdict means the escrow transaction is **not applied on the rejecting node** — the gamed job's funding vanishes from that node's state and the task is never claimable there. Escrow *return* to the poster is a separate mechanism (below), not part of the reject verdict. — **Reversibility:** costly — consensus-visible behavior; undo changes what honest nodes do with already-seen gamed jobs.
- **D-08-04 Claim-time backstop:** `TaskQueueImpl::GrabTask` runs `ValidatePrice` before `LockTask`; on reject it uses the existing `MarkTaskBad` skip. Belt-and-suspenders for catchup-synced tasks and any gate/visibility gap; cheap because the validator is pure. — **Reversibility:** reversible.

### Escrow return to poster (CONS-02)
- **D-08-05 Release trigger:** the **first honest rejector** constructs the consensus-certified `EscrowReleaseTx` back to the poster's `release_address` — immediate, no TTL wait, no poster action. Existing `EscrowReleaseTx{release_amount, release_address, original_escrow_hash}` fields carry everything needed. — **Reversibility:** reversible.
- **D-08-06 Authorization mechanism:** a **new typed consensus subject for rejection releases** (task ref + typed reject reason + escrow ref) that honest validators verify independently — reuses consensus subject machinery; no task result exists to ride the existing TASK_RESULT subject. — **Reversibility:** one-way — a new consensus subject type is a published protocol contract (Consensus.proto); removing it after nodes have certified subjects breaks compatibility.
- **D-08-07 Refund amount:** **full refund, no burn** — the escrow-release burn-basis-points do not apply to rejection refunds. Gaming is already prevented by rejection; penalties for repeat offenders were explicitly deferred in Phases 6/7. — **Reversibility:** reversible.
- Concurrent/duplicate releases of the same escrow are guarded by existing UTXO double-spend rules (a release spends the escrow UTXO; the second release fails as a double-spend).

### Rejection semantics & convergence (CONS-02, CONS-03)
- **D-08-08 Convergence definition:** convergence = **no honest node ever processes a job it did not verify**. Per-node fail-closed is acceptable: a `NO_COVERAGE` node skipping an honest job is harmless; a covered node processing an honestly-priced job is fine. Identical verdicts everywhere are NOT required (and NO_COVERAGE divergence is tolerated). — **Reversibility:** reversible — test assertions encode this invariant.
- **D-08-09 Rejection propagation:** "do whatever existing consensus does" — rejection propagation rides existing consensus mechanics (the rejection-release subject and validation verdicts); **no extra CRDT rejection marker** or side-channel record. — **Reversibility:** reversible.
- **D-08-10 Task cleanup:** **per-node skip only** — after rejection, each node independently never claims the task (gate + backstop); no network-wide claimable-list tombstone. Matches existing `MarkTaskBad` semantics; smaller diff. — **Reversibility:** reversible.

### Multi-node test (TEST-02)
- **D-08-11 Test home:** **extend the existing `ProcessingNodesTest` suite** with new test cases (3-node fixture: light poster + 2 processors). One suite, shared setup cost. — **Reversibility:** reversible.
- **D-08-12 Gamed-job construction:** post via the **real `ProcessImage` wire path**, then flip the loopback stub's served price (or the validator band via `SGNS_PRICEVAL_*` env) so the posted claim is out-of-band relative to what validator nodes observe. No hand-built Task proto injection for the multi-node case. — **Reversibility:** reversible.
- **D-08-13 Refund proof:** assert the poster's GNUS balance returns to its pre-post level (full refund per D-08-07) **and/or** `WaitForEscrowRelease` confirms the release on the poster's node. — **Reversibility:** reversible.

### the agent's Discretion
- Exact rejection-subject proto message name, fields, and field numbers in `Consensus.proto`; where the subject type constant lives (`SubjectTypeMatches` switch).
- Where the escrow→task cross-reference lookup lives (a `TransactionConsensusHandler` helper vs a `TransactionManager` query seam).
- How Pending verdicts get re-evaluated when the task record lands (reuse existing pending machinery).
- Release construction plumbing: reuse `AsyncPayEscrow`-style async pattern or a new dedicated helper.
- How the claim-time backstop obtains `PriceValidationInput` inputs (escrow fetch seam) without blocking `GrabTask`.
- Logging/metrics naming for gate verdicts; test helper organization inside `processing_nodes_test.cpp`.

### Folded Todos
None folded.
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements & roadmap
- `.planning/workstreams/tokenprice/REQUIREMENTS.md` — CONS-01..03, TEST-02; D-01..D-04 design decisions; OQ1 (hook point) resolved by this context
- `.planning/workstreams/tokenprice/ROADMAP.md` — Phase 8 goal and success criteria
- `.planning/workstreams/tokenprice/phases/07-price-validator/07-CONTEXT.md` — D-07-01..D-07-12 decisions this phase consumes (validator API, config, NO_COVERAGE self-heal, legacy rejection)
- `.planning/workstreams/tokenprice/phases/06-price-claim-wire-format-history/06-CONTEXT.md` — D-06-01..D-06-07 (escrow DAG timestamp as reference time, cost-binding input, history semantics)

### Consensus & transaction path (the integration surface)
- `SuperGenius/src/transaction/TransactionConsensusHandler.cpp` — `ValidateTransactionForConsensus` (~line 510: typed check chain), migration-allowlist `Pending()` precedent (~line 485), `reject_and_maybe_fail_local`
- `SuperGenius/src/transaction/TransactionConsensusHandler.hpp` — handler interface, validation entry points
- `SuperGenius/src/transaction/TransactionManager.cpp` — tx parse/revert dispatch (~line 117), `PayEscrow` (~line 1219), `AsyncPayEscrow` (~line 1309), `ParseEscrowTransaction` (~line 2836), `FetchTransaction(globaldb, escrow_path)` (~line 1256 context), `WaitForEscrowRelease` (~line 3062)
- `SuperGenius/src/blockchain/impl/proto/Consensus.proto` — subject types, `EmbeddedTransaction` with `escrow_release` field 7
- `SuperGenius/src/blockchain/Consensus.cpp` — `CheckSubject` (~line 4350: subject-type validation switch, TASK_RESULT precedent)
- `SuperGenius/src/account/proto/SGTransaction.proto` — `EscrowTx{dag_struct, utxo_params, amount}`, `EscrowReleaseTx{release_amount, release_address, escrow_source, original_escrow_hash}`, `DAGStruct.timestamp` (field 5)

### Task queue & receive path
- `SuperGenius/src/processing/impl/TaskQueueImpl.cpp` — `EnqueueTask` (~line 32), `GrabTask` (~line 123: claim scan + `IsProcessingValid` precedent), `MarkTaskBad` (~line 215), `CompleteTask` (~line 183)
- `SuperGenius/src/processing/impl/TaskKeys.hpp` — CRDT key namespace for tasks/claimables/locks
- `SuperGenius/src/account/GeniusNode.cpp` — `ProcessImage` (~line 2694–2790: `GetProcessCost`, `task.set_claimed_price`, `HoldEscrow`, `EnqueueTask` at ~line 2767), `ProcessingDone` (~line 3415: `AsyncPayEscrow`), `WaitForEscrowRelease` (~line 3754)

### Validator & price domain (Phase 7/6 outputs consumed)
- `SuperGenius/src/coinprices/PriceValidator.hpp` / `.cpp` — `ValidatePrice(PriceValidationInput, PriceValidatorConfig) -> PriceValidationResult` (8-value reason taxonomy), `ResolvePriceValidatorConfig()` + `SGNS_PRICEVAL_*` knobs, `ShouldTriggerRefetch(reason)`, `PriceObservationWindow(T, config)`
- `SuperGenius/src/coinprices/LocalPriceManager.hpp` — `QueryHistory(from, to) -> PriceHistoryStats{count, min, max}`
- `SuperGenius/src/coinprices/PriceFreshness.hpp` — `kFreshMaxAge`/`kStaleMaxAge` (window inputs)
- `SuperGenius/src/account/TokenAmount.hpp` — `CalculateCostMinions` (cost-binding oracle)

### Test infrastructure
- `SuperGenius/test/src/processing_nodes/processing_nodes_test.cpp` — 3-node fixture (light poster + 2 processors), loopback `HttpStubServer` price stub, `ScopedEnvVar` price-tier redirect, `wait_condition` helpers
- `SuperGenius/test/src/testutil/scoped_env.hpp` — RAII env-var guards
- `SuperGenius/test/src/price_validator/price_validator_test.cpp` — hermetic validator suite (22 tests, zero mocks)
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `ValidatePrice` + `ResolvePriceValidatorConfig` + `PriceObservationWindow` + `ShouldTriggerRefetch` — the entire decision core; Phase 8 only supplies inputs (`QueryHistory` + escrow fetch) and consumes verdicts
- `TransactionConsensusHandler` check chain + `Pending()` verdict machinery — the gate extends an existing, tested validation pipeline; the migration allowlist shows exactly how "can't decide yet" is expressed
- `MarkTaskBad`/`incompatible_jobs_` — ready-made claim-path rejection skip in `GrabTask`
- `EscrowReleaseTx` + `PayEscrow`/`AsyncPayEscrow` + `WaitForEscrowRelease` — release construction and confirmation precedent; refund reuses this machinery with `release_address` = poster
- `FetchTransaction(globaldb, escrow_path)` — the escrow-fetch seam the gate/backstop needs for `PriceValidationInput`
- `ProcessingNodesTest` fixture — 3 nodes, hermetic loopback price stub, local trust setup; TEST-02 extends it rather than building new harness

### Established Patterns
- Typed check chains returning `ValidationResult{Approve/Reject/Pending}` in consensus validation
- Consensus subjects as typed, independently verifiable payloads (`SubjectTypeMatches` switch in `CheckSubject`)
- Env-var-only runtime config with `SGNS_` prefix; fail-closed policies; pure-function + injectable-clock hermetic testing
- CRDT transactions committed to `processing_topic_` for task lifecycle records

### Integration Points
- Gate: escrow-tx branch of `ValidateTransactionForConsensus` — cross-reference the task by the escrow's claiming task (task lookup by `escrow_path` relationship), run `ValidatePrice`
- Backstop: `GrabTask` after `GetTask`/before `LockTask`, beside the existing `IsProcessingValid` check
- Release: first-rejector path builds the rejection subject + `EscrowReleaseTx`; poster observes via `WaitForEscrowRelease`
- ⚠ **Landmine for research/planning:** the rejector constructs a release referencing an escrow it did **not** apply locally (D-08-03). The consensus-certified release path must reconcile this (e.g., certification applies the referenced escrow, or the release is validated against the certified ledger view, not local state). This is the highest-risk unknown in the phase — the researcher must trace how certified transactions apply against locally-unapplied predecessors.
</code_context>

<specifics>
## Specific Ideas

- User's guiding principle, quoted: **"follow existing consensus mechanisms… maybe in TransactionManager"** and for propagation, **"do whatever existing consensus does"** — when in doubt, mirror the existing consensus/transaction pattern rather than inventing a parallel mechanism.
- The gate must never reject merely because the task hasn't arrived yet — Pending, per D-08-02.
- Test asserts economic effect (balance restored), not just artifact existence.
- Escrow return = full amount; burn basis points explicitly do not apply (D-08-07).
</specifics>

<deferred>
## Deferred Ideas

- Trust/reputation value for posters and consensus-applied penalties for repeat bad actors (carried from Phases 6/7; later milestone).
- Tolerance/window defaults derived from real GNUS volatility telemetry (carried from Phase 7; config knobs make this tunable).

### Reviewed Todos (not folded)
- "Fix Vulkan capability-probe deadlock/crash in ProcessingManager::Create path" — keyword-only match ("validator"), unrelated domain; re-reviewed this phase (also reviewed in Phase 7); remains an open testing todo in its own right.
</deferred>

---
*Phase: 8-Consensus Integration*
*Context gathered: 2026-10-06*
