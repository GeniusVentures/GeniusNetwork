# Phase 1: ELM Job Model & Funding - Research

**Researched:** 2026-09-09
**Domain:** ELM job schema (quicktype/SGProcessingManager) + hours-based escrow & three-clock derivation (SuperGenius `src/account` + `src/processing`)
**Confidence:** HIGH (every code claim below re-verified by direct inspection of the CURRENT `dev_elmruntime` working trees: SuperGenius @ `7f498073a`, SGProcessingManager @ `8fcd2be`; branches confirmed via `git branch --show-current`)

## Summary

Phase 1 rides entirely on existing machinery. The quicktype pipeline (`gnus-processing-schema.json` → `generated/*.hpp`) is fully understood, the regen toolchain is **installed and verified locally** (node v24.16.0, quicktype 23.2.6), and the schema's constraint system (`CheckConstraint` bounds/pattern → exception → `INVALID_JSON`) gives most of the parse-rejection matrix for free. The two research flags resolved decisively:

**(a) Escrow wall-clock accounting — DOES NOT EXIST.** The settlement path (`PayEscrow` → `BuildPayoutOutputs`, `TransactionManager.cpp:1205/1097`) distributes the **entire escrowed amount** as an even split across valid subtask results. No time is measured anywhere: `SubTaskResult` carries no timestamps, `ExecutionManifest` timing excludes fetch (captured after `GetCidForProc`, `ProcessingManager.cpp:1394-1413`), and there is **no refund path** — the requester's full escrow is always fully consumed (burn + peers + developers). Refund-by-measured-wall-clock must be *built*, not wired; the design (below) pins where.

**(b) ELM validation finalization — simpler than D-11 assumed.** The cross-subtask chunk-hash comparison in `ValidateResults` is keyed on serialized `ProcessingChunk` ids; production subtasks mint per-subtask-unique chunk ids (`tasksplit.cpp:69`) and `ProcessImage` never creates a validation subtask (`SplitTask(..., false, ...)` at `GeniusNode.cpp:2310`), so the comparison is **structurally inert in production today**. With one notional chunk per ELM subtask, `validation: none` needs **zero changes to `ValidateResults`** — the queue already finalizes on first-accepted-result (`m_results.emplace` first-wins, processed subtasks excluded from re-grab). D-11's "skip via job-type check" is a correction, not a requirement; a cheap defensive assertion at `FinalizeQueueProcessing` (which already parses `Task.json_data`) satisfies D-12's read-from-schema pattern.

**Primary recommendation:** Schema lands first in SGProcessingManager (root gains optional `job_type`/`elms[]`/`funding`/`validation`; `passes`/`inputs`/`outputs` move from schema-`required` to C++-enforced for non-ELM), then the SuperGenius side lands `GetElmProcessCost` (public, mirror of `GetProcessCost`), the three-clock derivation helper, the CRDT rate-record beside `escrow_path`, and `SetProcessingTimeout` wiring at queue creation — with the full ELM submit path deferred to Phase 4 exactly as the roadmap notes.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Billable wall-clock aggregates as **sum of per-subtask windows** — each subtask bills grab→publication independently; concurrent work items each bill their full window
- **D-02:** Measured wall-clock converts to billable hours by **truncation to milli-hours at PRECISION=6** ($0.0003/hr → 1 milli-hour = 0.3 minions); sub-second windows bill as 0 — requestor-favorable
- **D-03:** Deadline firing mid-generation **cancels at deadline**; subtask publishes `finish_reason: cancelled` with measured counts; unused escrow refunds; never bill past the declared maximum
- **D-04:** **Default-fill** — minimal job JSON = `job_type` + `elms[]` with manifest+input only. Defaults: `funding.maximum_processing_hours` = **1.0h** (escrow at hold = 300 minions ≈ $0.0003), temperature=1.0, top_p=1.0, `validation` = `none`
- **D-05:** **Out-of-range values reject at parse** with a structured error — never clamp. temperature ∈ [0,2], top_p ∈ (0,1], max_output_tokens > 0, hours > 0 with sane cap (~24h)
- **D-06:** **No new version field** — reuse `gnus_spec_version` (quicktype-constrained ==1); ELM block rides beside `passes[]` under the same root
- **D-07:** Duplicate `work_item_id`, missing/unknown fields with no default, unknown validation modes reject at parse with a structured error
- **D-08:** deadline = `maximum_processing_hours` exactly; subtask lock timeout = deadline + fixed grace (~+60s); all three clocks share one derivation source
- **D-09:** The three-clock derivation lives on the **SuperGenius side** (helper near `processing_tasksplit_elm` or a small clocks utility)
- **D-10:** Deadline is **per-subtask from its own grab**: deadline = grab_time + maximum_processing_hours, lock = deadline + grace
- **D-11:** `validation: none` finalizes on **first accepted result** — existing single-result path; hash comparison skipped via job-type/flag check at the validation call site *(research corrects: see Finding F2 — the check is structurally unnecessary for v1.0; keep as defensive assertion)*
- **D-12:** The validation-mode gate reads from the **job schema at the call site** — re-created `ProcessingManager` / parsed `Task.json_data`; no subtask-carried flags
- **D-13:** Schema carries the full enum `none|exact|redundant`; v1.0 implements `none` only — `exact`/`redundant` reject at parse as unimplemented

### Claude's Discretion
- Exact structured-error format/fields for parse rejections (follow existing quicktype/`CheckConstraint` conventions where possible)
- The precise lock-grace constant value (~60s suggested)
- The sane upper cap for `maximum_processing_hours` (suggested 24h) and upper-bound defaults for `max_output_tokens`
- Where the ELM block sits in the quicktype JSON schema file (beside `passes[]`, new top-level section)
- Unit-test structure for the parse-rejection matrix and three-clock derivation

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| JOB-01 | `elm_processing` job with `elms[]` work items (`work_item_id`, `elm_type`, manifest `uri`+`hash`, input pointer, generation settings) entirely in existing `Task.json_data` — no main-protobuf change | F3 (schema pipeline + root restructure), F6 (quicktype enforcement limits → C++ checks), F7 (structured-error patterns) |
| JOB-03 | Schema-level validation mode (`none\|exact\|redundant`) governs ELM result validation; text does not flow through chunk-hash float-tolerance regime | F2 (ValidateResults structurally inert for unique chunk ids; D-12 read pattern already exists at `FinalizeQueueProcessing`), F6 (enum + D-13 unimplemented-mode gate in C++) |
| FUND-01 | Deterministic funding `funding.maximum_processing_hours × $0.0003/hour` through existing `HoldEscrow`/`AsyncPayEscrow` mechanics — no negotiation, no price lookup | F4 (cost branch points), F5 (PRECISION=6 integer math), F8 (rate recording in CRDT, no proto change) |
| FUND-02 | Per-job clock alignment (lock ≈ deadline ≈ escrow max) replaces the fixed 15s lock for ELM jobs | F9 (`SetProcessingTimeout` wiring; queue proto propagates the value to peers automatically) |
| FUND-03 | Model download time billable within the escrow bound; over-time job reaches a terminal state (not a silent re-grab loop) | F1 (settlement measures nothing today — design), F10 (`BUDGET_EXCEEDED` currently yields NO published result → re-grab loop; envelope-carried terminal states close it) |
</phase_requirements>

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| ELM job schema shape + per-field bounds | SGProcessingManager (`gnus-processing-schema.json` + `generated/`) | — | Quicktype owns all wire-shape types; `CheckConstraint` gives bounds/pattern rejection at parse for free |
| Cross-field semantic validation (duplicate `work_item_id`, non-ELM-requires-passes, unimplemented validation modes, defaults fill) | SGProcessingManager `ProcessingManager::Init`/`CheckProcessValidity` (hand-written) | — | Quicktype cannot enforce `uniqueItems`/`minItems`/conditional-required; established codebase pattern is C++ gates beside the generated parse |
| Hours→minions cost computation | SuperGenius `GeniusNode::GetElmProcessCost` (new, public) | `TokenAmount`/`ScaledInteger` (PRECISION=6) | Cost is a node-side accounting concern; `GetProcessCost` precedent is public and unit-tested |
| USD→GNUS rate recording at hold time | SuperGenius `GeniusNode::ProcessImage` → CRDT `AtomicTransaction` (sibling key of `escrow_path`) | — | `EscrowTx` proto has no metadata field; multi-`Put` on one CRDT transaction is the established atomic pattern (`TaskQueueImpl::EnqueueTask`) |
| Three-clock derivation (deadline / lock / escrow max) | SuperGenius helper (near future `processing_tasksplit_elm.*` or a clocks utility) | — | D-09: the timeout is a SuperGenius queue concept; only SuperGenius consumes it today |
| Lock-timeout wiring | SuperGenius `ProcessingServiceImpl`/`ProcessingNode` at queue creation → `ProcessingSubTaskQueueManager::SetProcessingTimeout` → `CreateQueue` | queue gossip proto carries it to peers | `processing_timeout_length` is written into the queue proto once at `CreateQueue` and inherited by all peers via queue updates |
| Settlement refund by measured wall-clock | **Phase 4 implementation** (design pinned here) | `TransactionManager::BuildPayoutOutputs`/`PayEscrow` | See F1/F10 — refund output + artifact-carried wall-clock stamps |
| Splitter / work_item_id↔subtaskid map | **Phase 4** (design note only) | — | Roadmap boundary |

## Standard Stack

**Zero new dependencies** (workstream D-003). Everything needed exists in-tree and was verified on this machine.

### Core
| Component | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| quicktype (CLI) | 23.2.6 (installed globally; `quicktype --version` verified) | Regenerate `generated/*.hpp` from `gnus-processing-schema.json` | The repo's only sanctioned way to change schema types (SCHEMA-01..05 zero-hand-edit norm; README.md:48) |
| nlohmann_json + boost::optional | vendored (thirdparty) | Generated parse/serialize (`from_json`/`to_json`/`get_stack_optional`) | Already linked by `ProcessingBase` (`src/processingbase/CMakeLists.txt:25`) |
| `TokenAmount` / `ScaledInteger` | in-tree (`SuperGenius/src/account/TokenAmount.*`, `src/base/ScaledInteger.hpp`) | PRECISION=6 minion arithmetic | Existing fixed-point standard; `CalculateCostMinions` precedent |
| GTest | ~1.14 (thirdparty) | Unit tests both sides | Both repos' test framework; `SGPROC_TEST_DISCOVERY` gating applies to new SGProcessingManager targets |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Quicktype regen (new root fields) | Stuff ELM JSON into the existing free-form `metadata` map (`additionalProperties: true`, schema line 71-75) | **Rejected** — metadata is untyped `std::map<std::string, nlohmann::json>`; no `CheckConstraint` bounds, no duplicate detection, no structured rejection. Would silently accept malformed jobs, violating D-05/D-07 |
| New `ElmFunding` proto message | JSON-only | **Forbidden** — ELM-01/D-004: no proto changes |

**Installation:** none. Regen command (README.md:22-38, identical in `.github/workflows/generate-headers.yml:29-43`):
```bash
quicktype --src-lang schema --lang cpp --top-level SGNSProcessing \
  --code-format with-getter-setter --const-style west-const \
  --namespace sgns --type-style pascal-case --member-style underscore-case \
  --boost --source-style multi-source --include-location global-include \
  --out generated/SGNSProcMain.hpp gnus-processing-schema.json
```
Note: the CI auto-PR workflow triggers **only on `main`** (`generate-headers.yml:6-8`); work lands on `dev_elmruntime`, so regen is run locally and committed. New headers are auto-included in builds via `target_include_directories(ProcessingBase ... ../../generated)` (`src/processingbase/CMakeLists.txt:8`) and installed by root `CMakeLists.txt:23`.

## Package Legitimacy Audit

No packages installed by this phase. quicktype 23.2.6 already present on the machine (verified `quicktype --version`); node v24.16.0 / npm 11.15.0 present. No registry lookups required — **no audit applicable**.

## Architecture Patterns

### System Architecture Diagram (Phase-1 decision flow at submit)

```
GCS builds ELM job JSON (job_type="elm_processing", elms[], funding{}, validation)
        │
        ▼
GeniusNode::ProcessImage(jsondata)            GeniusNode.cpp:2257
        │
        ├─[1] sgns::sgprocessing::ProcessingManager::Create(jsondata)   ProcessingManager.cpp:419
        │        │
        │        ├─ nlohmann parse → quicktype from_json (Generators.hpp)
        │        │     ├─ bounds/pattern violated → CheckConstraint throws → INVALID_JSON   [free: D-05]
        │        │     └─ unknown enum string  → runtime_error → INVALID_JSON               [free]
        │        ├─ NEW pre-parse/C++ gates (follows Init:523-561 pattern):
        │        │     ├─ non-ELM job missing passes/inputs/outputs → structured error      [root-required moved to C++]
        │        │     ├─ duplicate work_item_id → structured error                          [D-07]
        │        │     └─ validation mode ∉ {none} → "unimplemented" structured error        [D-13]
        │        └─ NEW default-fill normalization (value_or pattern, ProcessingManager.cpp:1311-1313 precedent)
        │
        ├─[2] job_type sniff → isElm?
        │        ├─ YES → funds = GetElmProcessCost(funding)   [NEW, public; NO GetGNUSPrice call]
        │        │          max_minions = round(hours×1000) × 3 / 10   (rate 1.0; see F5)
        │        └─ NO  → funds = GetProcessCost(procmgr)     GeniusNode.cpp:2381  [UNTOUCHED: bytes→FLOP→CoinGecko]
        │
        ├─[3] Phase-1 ELM branch STOPS here (structured not-yet-splittable error);
        │      Phase 4 continues: ELM splitter → SetProcessingTimeout(derived) → hold → enqueue
        │
        └─ non-ELM continues byte-for-byte: chunk splitter (2293-2313) → HoldEscrow (2320)
              → CreateEscrowInfoCRDTTransaction (2330) [+ NEW sibling Put: elm rate | ELM only, Phase 4]
              → EnqueueTask (2332)

Escrow settlement (design pinned now, built Phase 4):
  OnResultReceived → IsProcessed → FinalizeQueueProcessing (parses Task.json_data: D-12 site)
      → ValidateResults (comparison inert for ELM: unique chunk ids, F2)
      → TaskResult → ProcessingDone (GeniusNode.cpp:2881) → AsyncPayEscrow (2928)
      → PayEscrow (TransactionManager.cpp:1205) → BuildPayoutOutputs (1097)
          TODAY: full amount, even split, NO refund, NO time measurement   [F1]
          ELM:   pay min(billable, escrow) by measured windows; refund remainder to escrow source
```

### Recommended Project Structure
```
SGProcessingManager/  (lands FIRST; submodule pointer bump follows)
├── gnus-processing-schema.json          # MODIFIED — job_type/elms/funding/validation + defs; root required relaxed
├── generated/                            # REGENERATED (zero hand-edits)
│   ├── Elm.hpp, ElmFunding.hpp, ElmValidationMode.hpp, ...   (names per quicktype pascal-case)
│   └── Generators.hpp / SgnsProcessing.hpp / SGNSProcMain.hpp (regenerated)
├── include/processingbase/ProcessingManager.hpp  # MODIFIED — new Error enum values (hand-written region)
├── src/processingbase/ProcessingManager.cpp      # MODIFIED — Init gates, default-fill helper, CheckElmValidity
└── test/ (new dir, e.g. test/processingbase/ or test/schema/)  # parse-rejection matrix (SGPROC_TEST_DISCOVERY gated)

SuperGenius/  (after pointer bump)
├── src/processing/processing_clocks_elm.hpp/.cpp  (or headers-only helper near tasksplit)  # NEW — three-clock derivation
├── src/account/GeniusNode.cpp/.hpp                # MODIFIED — job_type sniff, GetElmProcessCost (public), rate-record helper
└── test/src/                                      # cost + clocks + lock-timeout unit tests
```

### Pattern 1: Bounds rejection rides `CheckConstraint` — free at parse
**What:** JSON-Schema `minimum`/`maximum`/`pattern` on numeric/string fields become `ClassMemberConstraints` in the generated header; `set_*` calls `CheckConstraint` which throws `ValueTooLowException`/`ValueTooHighException`/`InvalidPatternException` (`generated/helper.hpp:84-140`); `from_json` calls the setters during parse (`Generators.hpp:539+`); `Init` catches `std::exception` → `Error::INVALID_JSON` (`ProcessingManager.cpp:571-578`).
**Use for:** temperature ∈ [0,2], top_p ∈ (0,1] (max=1 + min exclusiveLow→use min 0.000001 or C++ check — see pitfalls), hours ∈ (0, 24].
```json
// gnus-processing-schema.json (new definition) — bounds enforced AT PARSE by generated code
"generation_settings": {
  "type": "object",
  "properties": {
    "temperature": { "type": "number", "minimum": 0, "maximum": 2 },
    "top_p":       { "type": "number", "minimum": 0, "exclusiveMinimum": true, "maximum": 1 },
    "max_output_tokens": { "type": "integer", "minimum": 1 },
    "seed":        { "type": "integer", "minimum": 0 }
  }
}
```
Note: quicktype C++ emits `min_double_value`/`max_double_value` — verify whether `exclusiveMinimum` survives codegen; if not (likely), enforce `top_p > 0` in the C++ gate (one line).

### Pattern 2: Semantic gates follow the `Init` pre-parse interception pattern
**What:** `Init` already intercepts raw JSON *before* `from_json` for cross-field/enum-context checks that quicktype can't express, returning specific `Error` codes (`UNKNOWN_PASS_TYPE`, `MODEL_FORMAT_UNSUPPORTED`, `ProcessingManager.cpp:523-561`), and `CheckProcessValidity` does typed post-parse checks with `m_logger->error` + `outcome::failure` (`ProcessingManager.cpp:586+`).
**Use for:** duplicate `work_item_id` (loop over `elms[]`), `validation ∈ {exact, redundant}` → unimplemented error (D-13), non-ELM job missing `passes`/`inputs`/`outputs` (preserves current rejection after root-`required` relaxation), `elm_type` known-set check. New `Error` enum values are hand-added to `include/processingbase/ProcessingManager.hpp:82-95` (enum currently ends at `UNKNOWN_PASS_TYPE = 13`).

### Pattern 3: Defaults applied at consumption via `value_or` (never by quicktype)
**What:** quicktype C++ does NOT apply schema `default`s on parse (optional fields → `boost::none`). The codebase pattern is `get_*().value_or(default)` at the consumption site — precedent: `gpuMemoryBudget/outputArtifactBudget/deadlineMs` (`ProcessingManager.cpp:1311-1313`).
**Use for:** D-04 default-fill — hours=1.0, temperature=1.0, top_p=1.0, validation=`none`. Recommend one hand-written normalization helper (e.g., `ProcessingManager::GetElmJobNormalized()` or free functions in a small elm header) so the three-clock derivation and cost branch read exactly one defaulted view.

### Pattern 4: Escrow rate recording = sibling `Put` on the existing CRDT atomic transaction
**What:** `CreateEscrowInfoCRDTTransaction` (`GeniusNode.cpp:3209-3220`) puts the serialized escrow at `HierarchicalKey(escrow_path)` inside the transaction that `EnqueueTask` later commits. `AtomicTransaction` supports multiple `Put`s committed atomically — precedent: `TaskQueueImpl::EnqueueTask` puts N subtask keys + task key + claimable key in one transaction (`impl/TaskQueueImpl.cpp:32-67`).
**Use for:** record `{"usd_per_hour":0.0003,"usd_per_gnus":R,"minions":M,"maximum_processing_hours":H}` at `HierarchicalKey(escrow_path + "/elm_rate")` (or a sibling key convention the planner picks) in the same transaction. **`EscrowTx` proto has NO metadata field** (`SGTransaction.proto:120-125`: only `dag_struct`/`utxo_params`/`amount`) and `DAGStruct` fields are all semantically load-bearing — the sibling-key approach is the only no-proto-change option. `escrow_path` = lock_id = `"0x" + blake2b_256(job_id)` (`TransactionManager.cpp:1077-1079`).

### Anti-Patterns to Avoid
- **Hand-editing `generated/`** — regen wipes it; all shape changes go through the schema (SCHEMA-01..05).
- **Raising the 15s timeout globally** — per-job derivation only (`m_processingTimeout` is per-queue-manager; the derived value rides the queue proto).
- **Clamping out-of-range generation settings** — D-05 mandates reject, never clamp.
- **Calling `GetGNUSPrice()` in the ELM cost branch** — FUND-01 forbids price lookup; a failed lookup also zeroes cost and rejects the job (`GeniusNode.cpp:2381-2391` path), the opposite of deterministic.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Fixed-point minion arithmetic | Raw uint64 scaling math | `TokenAmount`/`ScaledInteger` (`FromString`/`FromDouble`/`Multiply`/`Divide`, PRECISION=6, `ScaledInteger.hpp:97-142`) | Rounding/overflow handling already solved; `CalculateCostMinions` precedent |
| Bounds/pattern validation | Custom range checks for schema-declared bounds | Schema `minimum`/`maximum`/`pattern` → generated `CheckConstraint` | Free, consistent errors; only cross-field checks need C++ |
| Structured parse errors | New exception hierarchy | Existing `Error` enum + `outcome::failure` + `m_logger->error` (Init/CheckProcessValidity pattern) | Matches every caller's expectations; GeniusNode maps failures to its own error codes |
| Timeouts/locks | New lock mechanism | `SetProcessingTimeout` + queue-proto `processing_timeout_length` | Wire exists end-to-end (manager → `CreateQueue:76` → `LockItem:49` → `UnlockExpiredItems:171`); it is merely uncalled |

## Common Pitfalls

### Pitfall 1: Root schema `required` blocks the minimal ELM job (D-04)
**What goes wrong:** Root schema requires `passes`, `inputs`, `outputs` with `passes` minItems 1 (`gnus-processing-schema.json:7,43,66`). D-04's minimal ELM job (`job_type` + `elms[]` only) cannot parse — `from_json` does `j.at("passes")` which throws `out_of_range` → `INVALID_JSON` (`Generators.hpp:588`).
**How to avoid:** Move `passes`/`inputs`/`outputs` out of root `required` (keep them as properties), enforce "non-ELM requires them" in the C++ gate. **Regression surface (SC-5):** today a job missing `inputs` is rejected inside `Create` with `INVALID_JSON`; after the change it must be rejected by the new C++ gate with an equivalent error — keep the rejection inside `Init` so the observable entry-point behavior (reject at `Create`) is unchanged. Note today's effective gate for `"passes": []` is actually downstream (`ParseBlockSize`→0→`PROCESS_COST_ERROR`, or empty subtasks→`INVALID_JSON` at `GeniusNode.cpp:2335-2337`) since quicktype does not enforce `minItems` — preserve by adding an explicit ≥1-pass check for non-ELM in the gate (stricter but same reject outcome; planner decides whether error-code parity matters for the empty-array edge).
**Warning signs:** any diff touching `ProcessImage`'s non-ELM path beyond the single `isElm` branch conditional.

### Pitfall 2: `to_json` round-trip emits new `null` keys for old jobs
**What goes wrong:** `ProcessImage` re-serializes the parsed job via `sgns::to_json(smalljson, procmgr->GetProcessingData())` (`GeniusNode.cpp:2280-2282`). Generated `to_json` writes EVERY property; `boost::optional` serializes absent as `null` (`helper.hpp:228-232`). After adding root `job_type`/`elms`/`funding`, every stored `task.json_data` gains `"job_type": null, "elms": null, ...` keys.
**Why it's acceptable:** today's round-trip already null-fills existing optionals; consumers re-parse via `from_json` which treats null as absent (`get_stack_optional`, `helper.hpp:198-204`). Behavior of the non-ELM pipeline is unchanged.
**How to avoid surprises:** do not add any consumer that string-compares `json_data`; flag the byte-diff in the Phase-4 regression gate definition (SC-5 scopes to cost/lock/validation *paths*, and the stored-JSON bytes were never input-identical anyway).

### Pitfall 3: Double precision in hours→milli-hours (escrow amount off-by-one)
**What goes wrong:** `1.3 × 1000 == 1299.9999999999998` in IEEE754; naive `uint64_t(hours * 1000)` truncates to 1299 milli-hours → escrow 0.3 minions short of the declared maximum.
**How to avoid:** use `std::llround(hours * 1000.0)` for the escrow-at-hold conversion (declared max must round UP deterministically); measured windows are integer ms from the start (no conversion). Keep the whole chain in uint64: `max_minions = llround(hours*1000) * 3 / 10` at rate 1.0 (1h → 1000×3/10 = 300 ✓ D-04).

### Pitfall 4: `SetProcessingTimeout` called after `CreateQueue` silently does nothing for this queue's peers
**What goes wrong:** `processing_timeout_length` is written into the queue proto once, inside `CreateQueue` (`processing_subtask_queue_manager.cpp:76`). A later `SetProcessingTimeout` only changes the local member (used by `CalculateGrabSubTaskTimeout:820`), never the published queue.
**How to avoid:** call `SetProcessingTimeout(derived)` on the queue manager **before** `AssignSubTasks`/`CreateQueue` runs. The creation path is `ProcessingServiceImpl::HandleNodeCreationTimeout` → `ProcessingNode::New(..., subTasks)` → `CreateSubTaskQueue` (`processing_node.cpp:39-44,207-212`); the task JSON is reachable there (`m_pendingTask` / `EnqueueSubTasks` return, `processing_service.cpp:526-535,667-700`). The queue manager is constructed in `ProcessingNode::Initialize` (`processing_node.cpp:126`) — thread a derived timeout (or the parsed funding) into `ProcessingNode::New`. Peers inherit the value automatically from queue gossip (`UpdateQueue` replaces the queue wholesale; `LockItem:49` reads the queue's field, not the local member) — verified end-to-end.

### Pitfall 5: Assuring "never silently re-grabbed" (SC-3/SC-4) — the failure loop is the default today
**What goes wrong:** An ELM subtask whose processing fails (or whose result never arrives) stays unprocessed; when its lock expires, `UnlockExpiredItems` frees it (`processing_subtask_queue.cpp:171-196`) and another node re-grabs — forever, with no terminal state. Today a processor-level `BUDGET_EXCEEDED` maps to `PROCESSING_FAILED` (`ProcessingManager.cpp:1466-1471`) → `ProcessingEngine` error sink → **no result published** (`processing_engine.cpp:143-149`) → exactly this loop.
**How to avoid (design pinned here; envelope implemented Phase 3, wiring Phase 4):** ELM terminal states must travel the *success-shaped* result path — the worker publishes a result envelope (artifact URI + one notional chunk hash + payout metadata) with `finish_reason: cancelled|error` so `CompleteSubTask` → `ValidateIndividualResult` (needs exactly 1 chunk hash, hex `node_address`, `developer_address`, 32-byte `token_id`, `developer_cut ≤ 1e6` — `processing_validation_core.cpp:190-262`) accepts and the subtask is marked processed. `ValidateResultData` requires every non-empty line of `ipfs_results_data_id` to be an `ipfs://` URI (`processing_subtask_queue_accessor_impl.cpp:610-666`) — envelope artifact URI complies.
**Warning signs:** ELM tests that assert `PROCESSING_FAILED` propagation instead of a published terminal envelope.

### Pitfall 6: quicktype silently DROPS schema constructs it can't model
**Verified against the generated tree:** `minItems` (root `passes` minItems 1 → no vector-length check anywhere in `Pass.hpp`/`SgnsProcessing.hpp`), `uniqueItems` (no support — duplicates need C++), `allOf/if/then` (schema lines 255-276 produce zero generated code — the "inference requires model" rule lives only in `CheckProcessValidity`), `default` (not applied on parse). **Consequence:** every D-05/D-07 guarantee that isn't a plain bound/pattern/enum MUST be a C++ gate — the schema alone is never sufficient. Design the rejection matrix as schema-bound (free) + C++ gate (explicit) and test both legs.

### Pitfall 7: Enum rejection has no field context — pre-parse intercept for the mode enum
**What goes wrong:** quicktype enum `from_json` is an if/else chain throwing a plain `runtime_error` on unexpected values (documented in-tree at `ProcessingManager.cpp:571-576`); the generic catch collapses it to context-free `INVALID_JSON`.
**How to avoid:** for `validation` and `elm_type`, either accept the generic `INVALID_JSON` for unknown strings (D-07 satisfied — it IS a parse rejection) or add recognized-set pre-parse checks returning dedicated error codes (the `kRecognizedPassTypes` pattern, `ProcessingManager.cpp:530-533`). D-13's "`exact`/`redundant` reject as unimplemented" must be a **post-parse** check (they parse fine; they're refused by policy).

### Pitfall 8: `m_maxSubtasksPerOwnership` default = 1
`m_defaultMaxSubtasksPerOwnership = 1` (`processing_subtask_queue_manager.cpp:24,27`) — each ownership cycle grabs one subtask then rotates ownership. Existing behavior, harmless for single-node v1.0, but multi-work-item ELM latency in Phase 4 will be ownership-rotation-bound. Out of Phase-1 scope; recorded so the E2E phase doesn't misdiagnose it.

## Code Examples

### Three-clock derivation (SuperGenius side, D-08/D-09/D-10) — sketch for the planner
```cpp
// processing_clocks_elm.hpp (new) — single derivation source for all three clocks
namespace sgns::processing
{
    struct ElmClocks
    {
        std::chrono::milliseconds deadline;      // = maximum_processing_hours, exact (D-08)
        std::chrono::milliseconds lockTimeout;   // = deadline + kLockGrace (60s, tunable — discretion)
        uint64_t                  escrowMinions; // = llround(hours*1000) * 3 / 10 at rate 1.0 (D-04)
    };
    // hours: already default-filled (1.0) and range-checked (0, 24] by the SGProcessingManager side
    ElmClocks DeriveElmClocks( double maximum_processing_hours );
}
```

### ELM cost branch (public, mirrors `GetProcessCost`'s testability)
```cpp
// GeniusNode.hpp — beside GetProcessCost (GeniusNode.hpp:367)
uint64_t GetElmProcessCost( const sgns::sgprocessing::ProcessingManager &procmgr ); // or (json) — planner picks
// Implementation: NO GetGNUSPrice() call; minions via integer path (Pitfall 3);
// rate constant recorded later at hold time via the CRDT sibling Put (Pattern 4).
```

### Duplicate-id + mode gates (SGProcessingManager, follows Init's existing pattern)
```cpp
// Post-parse, inside CheckProcessValidity (or a new CheckElmValidity called from it):
if ( auto elms = processing_.get_elms() )
{
    std::set<std::string> seenIds;
    for ( const auto &elm : elms.value() )
    {
        if ( !seenIds.insert( elm.get_work_item_id() ).second )
        {
            m_logger->error( "Duplicate work_item_id: {}", elm.get_work_item_id() );
            return outcome::failure( Error::DUPLICATE_WORK_ITEM_ID ); // new enum value, hand-written header
        }
    }
    if ( auto mode = processing_.get_validation() ;
         mode && *mode != sgns::ElmValidationMode::NONE )
    {
        return outcome::failure( Error::ELM_VALIDATION_UNIMPLEMENTED ); // D-13
    }
}
```

### Lock-timeout unit test shape (SC-3, no full node needed)
```cpp
// ProcessingSubTaskQueue-level: derived timeout keeps the lock past 60s
ProcessingSubTaskQueue queue( "nodeA", []{ return nowMs; } );
// ... CreateQueue with processing_timeout_length = 70'000 ...
queue.LockItem( idx, nowMs );                       // processing_subtask_queue.cpp:38-56
EXPECT_FALSE( queue.UnlockExpiredItems( nowMs + 60'000 ) ); // lock_expiration = grab+70s → still held
// And the wiring leg: queue manager test — SetProcessingTimeout(hours+grace) BEFORE CreateQueue
// asserts queue->processing_queue().processing_timeout_length() == derived ms (set at :76).
```

## Key Findings (the two mandated verification gaps + pinned code detail)

### F1 — Escrow settlement measures NOTHING; refund must be built (RESEARCH FLAG a — RESOLVED)
Trace, all `SuperGenius/src/`, verified line-level:
- Hold: `GeniusNode::ProcessImage:2320` → `TransactionManager::HoldEscrow:1073` — creates `EscrowTransaction` (amount, UTXO params only), reserves UTXOs, returns `(txId, (lock_id, serialized escrow bytes))`. **No timestamps, no rate, no metadata.**
- Record: `CreateEscrowInfoCRDTTransaction:3209` puts the serialized `EscrowTx` at `HierarchicalKey(escrow_path)`; committed by `EnqueueTask` (`impl/TaskQueueImpl.cpp:66`).
- Settlement trigger: results → `FinalizeQueueProcessing` (`processing_subtask_queue_accessor_impl.cpp:422`) → owner builds `TaskResult` → sink → `GeniusNode::ProcessingDone:2881` → `AsyncPayEscrow:2928` (`TransactionManager.cpp:1279`).
- Payout: `PayEscrow:1205` fetches the escrow, then `BuildPayoutOutputs:1097` splits **`escrow_tx->GetAmount()` in full**: `per_result = available / valid_results.size()` (even split), remainder-to-burn, developer cuts floored. **No time input, no refund output, requester's escrow always fully consumed.**
- No wall-clock anywhere in the result chain: `SubTaskResult` (`SGProcessing.proto:88-100`) has no time fields; queue `lock_timestamp` is in an *aggregated ownership time base*, not wall epoch (`UpdateQueueTimestamp`, `processing_subtask_queue_manager.cpp:744-761`); `ExecutionManifest.startTimeUsec/endTimeUsec` are wall-clock but are captured **after** `GetCidForProc` fetch (`ProcessingManager.cpp:1394-1413`) — download excluded — and live only in-process (`GetLastManifest`).

**What must change (design for Phase 1; implementation Phase 4 per roadmap SC-2):**
1. **Measurement:** per-subtask wall-clock stamps `grab_time_usec`/`finish_time_usec` carried in the ELM result **envelope artifact** (schema field, no proto change), written by the worker at `ProcessingEngine::ProcessSubTask` entry/`CompleteSubTask` publication. The finalizing node already has an artifact-fetch lambda (`fetchOutputData`, `accessor_impl.cpp:379-411`) to read them at finalization.
2. **Billable computation:** sum of per-subtask windows (D-01), truncate each to milli-hours, `billable_minions = Σ milli_hours × 3 / 10` (rate 1.0; D-02 floor, requestor-favorable), capped at escrow max (D-03).
3. **Payout rework:** extend `BuildPayoutOutputs` for ELM tasks: peers+developer paid from `billable_minions` (split rule — even across work items, planner/owner confirms), **refund output** of `escrow − billable` to `escrow_tx->GetSrcAddress()` (source address already accessed in `PayEscrow:1240` for the CRDT topic — available for an output too). Keep total-conservation check (`TransactionManager.cpp:1188-1196` shape).
4. **Rate availability at settlement:** read the sibling CRDT key (Pattern 4) or the task JSON (`funding` reachable via `task_queue_->GetTask` in `ProcessingDone`).

### F2 — ELM validation finalization: no `ValidateResults` change needed for `none` (RESEARCH FLAG b — RESOLVED, corrects D-11's mechanism)
- Cross-subtask comparison (`processing_validation_core.cpp:118-161`) fires only when ≥2 subtasks contribute the **same serialized chunk key**. Production chunk ids embed the per-subtask uuid (`tasksplit.cpp:69` `CHUNK_%d_%d`), and the only sharing mechanism — the validation subtask (`addvalidationsubtask`, `tasksplit.cpp:75-84`) — is **never enabled in production** (`ProcessImage` passes `false`, `GeniusNode.cpp:2310`). So the comparison is inert for any splitter that mints subtask-unique chunk ids (the ELM splitter's one-notional-chunk design does, by construction).
- First-accepted-result finalization already exists: local path `CompleteSubTask:218` validates→stores→marks processed→publishes; external path `OnResultReceived:272` does the same and `m_results.emplace` is first-wins (`:307`); processed subtasks are excluded from enabled indices (`UpdateUnprocessedSubTaskIndices`) so they are never re-grabbed; `IsProcessed` → `FinalizeQueueProcessing` completes the task.
- Binding constraints the ELM envelope MUST satisfy (`ValidateIndividualResult:190-262`): `chunk_hashes_size() == chunkstoprocess_size()` (exactly 1), non-empty non-duplicate hash, hex `node_address`, non-empty `developer_address`, 32-byte `token_id`, `developer_cut ≤ 1e6` — all populated by existing code paths (`processing_engine.cpp:127-128`, `processing_core_impl.cpp:133-135`).
- **D-12 confirmed implementable as described:** `FinalizeQueueProcessing` already parses `Task.json_data` into `SgnsProcessing` for job parameters (`accessor_impl.cpp:337-375`, including the malformed-JSON fail-safe) — reading `validation` from the same parse is a three-line extension.
- **Correction to D-11:** no behavioral job-type branch in `ValidateResults` is required for v1.0. Optional cheap defensive assertion at the call site (ELM ⇒ mode == none) aligns with D-12 and costs nothing; a real gate only becomes necessary when `exact`/`redundant` are implemented (post-v1.0).

### F3 — Quicktype pipeline (zero-ambiguity spec for the schema task)
| Item | Verified fact |
|------|---------------|
| Schema file | `SGProcessingManager/gnus-processing-schema.json` (draft-07; root `required` at line 7) |
| Regen command | README.md:22-38 (quoted above); identical in CI `.github/workflows/generate-headers.yml:29-43`; CI fires only on `main` → local regen + commit on `dev_elmruntime` |
| Toolchain | quicktype 23.2.6, node 24.16.0 **installed on this machine** (verified) |
| Output layout | `--source-style multi-source` → one header per definition (43 files today) + `Generators.hpp` (all `from_json`/`to_json`) + `helper.hpp` (`CheckConstraint`, `ClassMemberConstraints`, optional accessors) + `SGNSProcMain.hpp` umbrella |
| Bounds mechanics | schema `minimum/maximum` → `min/max_double_value` (or `_int_`) → `CheckConstraint` throws typed exception in `set_*` during `from_json` (`helper.hpp:84-117`, `SgnsProcessing.hpp:73` shows the `gnus_spec_version==1` constraint live) |
| Pattern mechanics | `pattern` → `std::regex` check → `InvalidPatternException` (`helper.hpp:129-140`; `name`/`version` constraints live at `SgnsProcessing.hpp:34-36`) |
| Enum mechanics | if/else chain, unknown value → plain `runtime_error` → caught as `INVALID_JSON` (`Init` catch, `ProcessingManager.cpp:571-578`) |
| Not enforced by generated C++ | `minItems`, `uniqueItems`, `if/then/else`, `oneOf`, `default` (all verified absent in generated code; semantics live in C++ gates) |
| Build integration | `ProcessingBase` includes `../../generated` (`src/processingbase/CMakeLists.txt:8`); root installs `generated/` (`CMakeLists.txt:23`); new headers need no CMake edits |
| `gnus_spec_version` | double, constrained `==1` (`SgnsProcessing.hpp:33,73`) — D-06 basis confirmed; unsupported versions already reject at parse |

### F4 — `ProcessImage` branch points (SC-5 blast radius)
| Site | Line (verified) | ELM branch action | Must NOT touch |
|------|------|-------------------|----------------|
| Entry / txn-state check | `GeniusNode.cpp:2257-2263` | shared, unchanged | — |
| `ProcessingManager::Create` | `:2264` | shared; ELM accept via schema change | non-ELM rejects stay in `Init` gates |
| Cost | `:2265` → `GetProcessCost:2381` | sniff `job_type` (readable from `procmgr->GetProcessingData()` once schema adds the field); ELM → `GetElmProcessCost`; **no CoinGecko** | `GetProcessCost` body unchanged |
| json round-trip + task fields | `:2277-2286` | shared (null-key growth — Pitfall 2) | — |
| Splitter loop | `:2290-2313` | ELM → structured not-splittable-yet error in Phase 1 (see Open Question 1); Phase 4 replaces with ELM splitter | loop body byte-identical for non-ELM |
| Escrow hold + CRDT | `:2319-2330` | Phase 4 wires ELM here + rate sibling-Put | sequence unchanged |
| Enqueue | `:2332` | Phase 4 | unchanged |

### F5 — Minion arithmetic for `hours × $0.0003` (PRECISION=6)
- Units: 1 minion = 10⁻⁶ GNUS (`TokenAmount.hpp:24`). $0.0003/h; at USD→GNUS rate `R`: `minions = hours × 0.0003 / R × 10⁶ = milli_hours × 0.3 / R`.
- **D-04's "300 minions ≈ $0.0003" implies R = 1.0** `[ASSUMED — see A1]`. Integer path at R=1: `minions = milli_hours × 3 / 10` (floor = D-02 requestor-favorable); 1.0h → 300 ✓.
- Toolchain: `TokenAmount::New`/`Multiply`/`Divide` wrap `ScaledInteger` at PRECISION=6 (`TokenAmount.cpp:20-60`); `CalculateCostMinions:65` is the byte-based contrast (bypassed by ELM). Keep the escrow-max computation in pure uint64 (Pitfall 3); `ScaledInteger` if R becomes configurable non-1.
- Range sanity at cap 24h: 24 × 300 = 7,200 minions — trivially inside uint64.

### F6 — Where the USD→GNUS rate can be recorded today (no proto change)
- `EscrowTx` proto: only `dag_struct`/`utxo_params`/`amount` (`SGTransaction.proto:120-125`); `DAGStruct` (line 4-14) fields all load-bearing. **No in-transaction free field exists.**
- Viable today: sibling CRDT key in the same atomic transaction as the escrow record (Pattern 4; multi-Put precedent `TaskQueueImpl.cpp:45-64`). Atomic with escrow + task enqueue (single `Commit`).
- Readable at settlement by: `PayEscrow`'s CRDT access (`FetchTransaction:1227`) — same GlobalDB; and/or task JSON via `GetTask`.

### F7 — Structured-error pattern at `Create` (~419) — verified shape to follow
`Create:419` → `Init:429`: (1) pre-parse raw-JSON interception with recognized-sets → dedicated `Error` codes (`:523-561`); (2) `nlohmann::json::exception` → `INVALID_JSON` (`:566-569`); (3) `std::exception` (quicktype enum/constraint throws) → `INVALID_JSON` (`:570-578`); (4) `CheckProcessValidity` typed post-parse checks with `m_logger->error` + `outcome::failure` (`:586+`). New ELM errors: extend the hand-written `Error` enum (`include/processingbase/ProcessingManager.hpp:82-95`, next free = 14) — the enum is NOT generated; the rejection matrix maps: bounds/pattern/enums → free via quicktype; duplicates/conditional-required/unimplemented-mode/`top_p>0` → C++ gates.

### F8 — Lock/timeout wiring path (verified end-to-end)
Constructor default 15s (`processing_subtask_queue_manager.cpp:21`); `SetProcessingTimeout:28` has **zero production callers** (re-verified: definition + header only); `CreateQueue:76` writes `m_processingTimeout.count()` into the queue proto; `LockItem` (`processing_subtask_queue.cpp:49`) sets `lock_expiration = now + queue.processing_timeout_length()`; `UnlockExpiredItems:171` frees expired locks of *enabled* (unprocessed) items; peers inherit the queue's value via gossip (`UpdateQueue`/`ProcessSubTaskQueueMessage:396`). Wiring point: before `CreateSubTaskQueue` in `ProcessingNode::New` (`processing_node.cpp:39-44`), fed from the task JSON available at `ProcessingServiceImpl::HandleNodeCreationTimeout:667-700` / `m_pendingTask`. SC-3's t>60s no-re-grab property = derived timeout > 60s ⇒ `UnlockExpiredItems` no-op while held; unit-testable at `ProcessingSubTaskQueue` level without a node.

### F9 — `BUDGET_EXCEEDED` terminal-state gap (SC-4)
Processor stage exists (`ProcessingErrorStage::BUDGET_EXCEEDED`, `processing_processor.hpp:41`; mapped in `ProcessInternal:1416-1471`), but every terminal error returns `PROCESSING_FAILED` — no result → error sink → unprocessed subtask → lock expiry → re-grab loop (F2/Pitfall 5 trace). Phase-1 design fix: ELM terminal states ride the result path as a published envelope (`finish_reason`) satisfying `ValidateIndividualResult`'s structural checks; the cancel mechanism itself is Phase 3 (approved MNN fork `USER_CANCEL`, D-002).

### F10 — Drift check vs workstream research
All previously published anchors re-verified on the current tree; drift is ±5 lines only, no semantic drift: `ProcessImage` 2257 ✓; `GetProcessCost` **2381** (docs said ~2388); `HoldEscrow` call 2320 ✓; `CreateEscrowInfoCRDTTransaction` 3209 ✓; queue-manager 15s default line 21 ✓; `ProcessingManager::Create` 419 ✓; `TokenAmount::CalculateCostMinions` 65 ✓; `SGProcessing.proto:61` ✓; `processing_core_impl.cpp` manager-create **87** (docs said 91), `GetModelNodeFromJson` **96** (docs said 98); `ValidateResults` block `processing_validation_core.cpp:47-186`; `PayEscrow:1205` / `AsyncPayEscrow:1279` / `BuildPayoutOutputs:1097` ✓.

## Runtime State Inventory

Not a rename/refactor/migration phase — **skipped** (greenfield feature riding existing wires; no stored data, OS state, secrets, or build artifacts carry renamed strings).

## Common Pitfall (process-level, from workstream PITFALLS still binding here)

- **Submodule commit order:** schema lands in SGProcessingManager (`dev_elmruntime`) → commit → SuperGenius pointer bump → SuperGenius branch work compiles against it → root repo pointer chain (PITFALLS 15.4). SuperGenius code must not compile against uncommitted submodule state.
- **New test targets respect `SGPROC_TEST_DISCOVERY` gating** (`test/execution/CMakeLists.txt:3-20` pattern: unconditional `add_test` + gated `gtest_discover_tests`) or the SuperGenius parent build re-breaks.
- **CTest `TIMEOUT` properties** on any new long test; wait-condition assertions (existing `assertWaitForCondition` helper, `test/src/processing_nodes/processing_nodes_test.cpp:530`).

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Cost = bytes→FLOP→CoinGecko (`GetProcessCost:2381`) | ELM: hours × fixed rate, no lookup (this phase) | this phase | Deterministic escrow; no network dependency at submit |
| Fixed 15s lock for all jobs | Per-job derived lock via existing `SetProcessingTimeout`/queue proto (this phase) | this phase | Long ELM subtasks no longer re-grabbed |
| Settlement = full escrow, even split | (Phase 4) measured wall-clock + refund — design pinned in F1 | — | SC-4 semantics fixed here |

**Deprecated/outdated in-tree facts to not rely on:** none found — the workstream research docs remain accurate for this phase's anchors (F10).

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | USD→GNUS rate for v1.0 is a **fixed constant 1.0** (derived from D-04's "1.0h → 300 minions ≈ $0.0003"); recorded in CRDT, never fetched | F5, F6, Patterns | If the owner intends a different constant or a config-sourced rate, only the constant's home changes (the integer formula generalizes via `ScaledInteger`); planner should confirm the number in the first checkpoint |
| A2 | Interim Phase-1 ELM submit stops **before** `HoldEscrow` (structured not-yet-splittable error) because a hold without a completable task strands reserved UTXOs (no un-reserve API short of payout) | F4, Open Questions | If the owner wants escrow exercised end-to-end in Phase 1, a minimal subtask path would have to be pulled forward from Phase 4; SC-2 would then verify via `ProcessImage` instead of unit-level |
| A3 | `exclusiveMinimum` on `top_p` may not survive quicktype C++ codegen (unverified for 23.2.6) — fallback one-line C++ gate `top_p > 0` | Pattern 1, Pitfall 6 | None — either mechanism satisfies D-05; verify at regen time and keep the C++ check regardless (belt-and-braces) |

## Open Questions (RESOLVED)

> **All three questions were resolved by the project owner at plan review (2026-09-09) and are locked into the plans as owner decisions OD-1/OD-2/OD-3.** Q1→OD-1 (reject before `HoldEscrow` with structured `ELM_SUBMIT_UNAVAILABLE` error; SC-2 verified via public `GetElmProcessCost` + rate-record unit test); Q2→OD-2 (`R = 1.0`, named constant `kUsdPerGnusRate` following the existing `GetProcessCost` USD-conversion shape); Q3→OD-3 (proportional-by-measured-window refund split).

1. **Interim ELM submit behavior in `ProcessImage` (Phase 1)** — **RESOLVED → OD-1: reject with structured error before `HoldEscrow`**
   - What we know: splitter + full wiring are Phase 4 (CONTEXT domain, ROADMAP note). Holding escrow without a completable task strands reserved UTXOs (`ReserveUTXOs` in `HoldEscrow:1090`; no release path short of payout).
   - What's unclear: whether SC-2's "escrow held … equals …" is satisfied unit-level (public `GetElmProcessCost` + rate-record helper + review of the hold call site) or demands a live hold in Phase 1.
   - Recommendation: branch returns a structured `ELM_SUBMIT_UNAVAILABLE` error before `HoldEscrow`; SC-2 verified via `GetElmProcessCost` (public, like `GetProcessCost` which tests already call directly, `account_management_test.cpp:308`) + a rate-record unit test. Confirm with owner at plan review.
2. **Rate constant value (A1)** — **RESOLVED → OD-2: `R = 1.0`** (named constant `kUsdPerGnusRate` in `processing_clocks_elm.hpp`, recorded in the `elm_rate` CRDT sibling key at hold time; follows the existing `GetProcessCost`/`CalculateCostMinions` USD-conversion shape with the deterministic constant replacing `GetGNUSPrice()`).
3. **Refund split rule for multi-work-item ELM settlement (Phase-4 implementation, design now)** — **RESOLVED → OD-3: proportional-by-measured-window** (each subtask settles by its own measured grab→publication wall-clock window, matching D-01 sum-of-per-subtask billing; explicitly supersedes even-split for ELM).

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| quicktype CLI | schema regen (SGProcessingManager) | ✓ | 23.2.6 (verified `quicktype --version`) | — |
| Node.js / npm | quicktype runtime | ✓ | 24.16.0 / 11.15.0 | — |
| CMake + MSVC 2022 toolchain | both repos' builds | ✓ | per repo build presets | — |
| GTest | unit tests | ✓ | ~1.14 (thirdparty) | — |
| CoinGecko reachability | **NOT required by ELM** (required only by legacy non-ELM cost tests) | n/a | — | ELM branch is offline-deterministic by design |

**Missing dependencies with no fallback:** none.
**Missing dependencies with fallback:** none.

External-package installation: **none** — no legitimacy gate triggers.

## Security Domain

**ASVS level 1 (config: `security_enforcement: true`, `security_asvs_level: 1`).**

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|------------------|
| V2 Authentication | no | phase touches no auth surfaces |
| V3 Session Management | no | — |
| V4 Access Control | partial | escrow spend authority unchanged (existing signature paths: `EscrowTransaction::MakeSignature`, `PayEscrow` input signing) — ELM adds no new spenders |
| V5 Input Validation | **yes** | JSON-schema bounds + enum rejection at parse (`CheckConstraint`), C++ gates for duplicates/conditional-required; reject-never-clamp (D-05) — this phase's core deliverable |
| V6 Cryptography | no new crypto | sha256/keys untouched; rate record is plain CRDT data |

### Known Threat Patterns for this change

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Malformed/adversarial `Task.json_data` crashes a validating node | DoS | existing fail-safe pattern (`FinalizeQueueProcessing` catch → log + fallback, `accessor_impl.cpp:355-368`); new gates follow the same try/catch discipline |
| Requestor under-declares hours to underfund, node computes for free | Economic | escrow max computed from the *declared* hours at submit (server-side, from parsed schema — never from a client-supplied cost field); hours bounded (0, 24] at parse |
| `work_item_id` used in filesystem paths later (Phase 2/4 hazard) | Tampering | constrain charset at schema level now (`pattern: "^[A-Za-z0-9_-]+$"` — same pattern as root `name`, schema line 12) so later phases never interpolate arbitrary strings |
| Over-time job loops forever burning node compute (griefing) | DoS/Economic | three-clock derivation + terminal published state (SC-3/SC-4) — this phase's design prevents the loop |

## Sources

### Primary (HIGH confidence — all verified in the current working tree)
- `SuperGenius/src/account/GeniusNode.cpp` — ProcessImage:2257-2357, GetProcessCost:2381-2410, GetGNUSPrice:2412-2431, GetCoinprice:3019-3073, CreateEscrowInfoCRDTTransaction:3209-3220, ProcessingDone:2881-2955
- `SuperGenius/src/account/TransactionManager.cpp` — HoldEscrow:1073-1102, BuildPayoutOutputs:1097-1197, PayEscrow:1205-1277, AsyncPayEscrow:1279-1310, WaitForEscrowRelease:2781-2833
- `SuperGenius/src/account/EscrowTransaction.cpp` / `src/account/proto/SGTransaction.proto` (EscrowTx:120-125, DAGStruct:4-14)
- `SuperGenius/src/processing/` — `processing_subtask_queue_manager.cpp` (15s default:21, SetProcessingTimeout:28, CreateQueue:39-118 incl. :76, ProcessPendingSubTaskGrabbing:181-335, UpdateQueueTimestamp:744-761, CalculateGrabSubTaskTimeout:816-842), `processing_subtask_queue.cpp` (LockItem:38-56, UnlockExpiredItems:171-196), `processing_validation_core.cpp` (ValidateResults:47-186, ValidateIndividualResult:190-262), `processing_subtask_queue_accessor_impl.cpp` (CompleteSubTask:218-266, OnResultReceived:272-330, FinalizeQueueProcessing:332-434 incl. task-JSON parse:337-375 + fetchOutputData:379-411, ValidateResultData:610-666), `processing_engine.cpp` (grab/complete/publish:63-153), `processing_node.cpp` (New:11-46, Initialize:120-162, CreateSubTaskQueue:207-212), `processing_service.cpp` (HandleRequestTimeout:490-560, HandleNodeCreationTimeout:661-775), `impl/TaskQueueImpl.cpp` (EnqueueTask:32-68), `impl/processing_core_impl.cpp` (ProcessSubTask:67-160), `processing_tasksplit.cpp` (SplitTask:44-96), `proto/SGProcessing.proto` (Task:9-15, SubTask:23-30, ProcessingQueue:53-61, SubTaskResult:88-100)
- `SuperGenius/src/account/TokenAmount.hpp` (PRECISION:24) / `.cpp` (CalculateCostMinions:65), `src/base/ScaledInteger.hpp` (46-142)
- `SGProcessingManager/` — `gnus-processing-schema.json` (root required:7; metadata:71-75; pass budget fields:235-253; allOf/if/then:255-276), `generated/SgnsProcessing.hpp` (constraints:27-36,73), `generated/helper.hpp` (CheckConstraint:84-140, optional accessors:142-210), `generated/Generators.hpp` (SgnsProcessing from_json:584-603), `generated/Pass.hpp` (no minItems trace), `README.md` (regen command:22-38), `.github/workflows/generate-headers.yml` (main-only:6-8), `src/processingbase/ProcessingManager.cpp` (Create:419, Init:429-584, CheckProcessValidity:586+, ParseBlockSize:1242-1264, ProcessInternal budgets:1311-1313, deadline timer:1380-1391, timing capture:1394-1413, BUDGET_EXCEEDED mapping:1458-1471), `include/processingbase/ProcessingManager.hpp` (Error enum:82-95), `src/processingbase/CMakeLists.txt` (:8), `CMakeLists.txt` (:23), `test/execution/CMakeLists.txt` (SGPROC_TEST_DISCOVERY:3-20), `include/execution/execution_context.hpp` (ExecutionContext:123-155), `include/artifacts/artifact_types.hpp` (TerminalState:28-35)
- Workstream research (`.planning/workstreams/elmbridge/research/` SUMMARY/ARCHITECTURE/PITFALLS) — used as scope map; every code anchor re-verified (F10)
- Toolchain: `quicktype --version` → 23.2.6; `node --version` → 24.16.0 (run in terminal, 2026-09-09); branches: SuperGenius `dev_elmruntime` @7f498073a, SGProcessingManager `dev_elmruntime` @8fcd2be (`git submodule status`)

### Secondary / Tertiary
- None used — no external libraries or documentation were needed (zero-new-dependency phase; all claims in-tree).

## Metadata

**Confidence breakdown:**
- Schema pipeline & parse-rejection mechanics: HIGH — every mechanism verified in generated code + Init's own comments
- Escrow settlement trace (F1): HIGH — full HoldEscrow→PayEscrow chain read line-level; negative claim ("no time measurement, no refund") verified by absence across `SubTaskResult` proto, settlement code, and manifest timing scope
- Validation finalization (F2): HIGH — comparison keying, validation-subtask flag, first-wins emplace, processed-set exclusion all verified
- Rate constant (A1) / interim submit behavior (A2): MEDIUM — derived from CONTEXT arithmetic and code constraints; owner confirmation queued

**Research date:** 2026-09-09
**Valid until:** 2026-10-09 (stable internal codebase; re-verify line numbers only if `dev_elmruntime` advances past 7f498073a / 8fcd2be)
