# Phase 1: ELM Job Model & Funding - Context

**Gathered:** 2026-09-09
**Status:** Ready for planning

<domain>
## Phase Boundary

An `elm_processing` job can be expressed, validated, priced, and escrowed entirely through job JSON riding the existing `Task.json_data` — the contract every later phase consumes. This phase delivers:

1. **ELM job schema** (quicktype regen in SGProcessingManager, zero hand-edits to `generated/`): `job_type: "elm_processing"` discriminator, `elms[]` work items (unique `work_item_id`, manifest `uri`+`hash`, input pointer, generation settings), funding block, validation-mode enum
2. **Hours-based cost branch** (SuperGenius, after submodule pointer bump): `GetElmProcessCost` = `funding.maximum_processing_hours` × $0.0003/hour → minions at PRECISION=6, no CoinGecko lookup; USD→GNUS rate recorded in the escrow transaction at hold time
3. **Three-clock rule**: lock timeout, execution deadline, and escrow maximum all derived from `funding.maximum_processing_hours` in one place
4. **Validation-mode schema decision**: `none|exact|redundant` enum with `none` the v1.0 default and the only implemented mode
5. **`work_item_id ↔ subtaskid` mapping DESIGN** (implementation is Phase 4's splitter)
6. **Escrow-settlement semantics design** (declared max escrowed up front; settled by measured wall-clock, subtask grab → publication, model download included; unused remainder refunded)

**Out of scope (Phase 2+):** manifest resolution/cache implementation, processor code, splitter implementation, E2E wiring. **Non-ELM path:** byte-for-byte unchanged (SC-5 regression gate).

Requirements: JOB-01, JOB-03, FUND-01, FUND-02, FUND-03.

</domain>

<decisions>
## Implementation Decisions

### Escrow & Settlement Semantics
- **D-01:** Billable wall-clock aggregates as **sum of per-subtask windows** — each subtask bills grab→publication independently; concurrent work items each bill their full window (requestor pays for compute used, matching the per-work-item envelope shape)
- **D-02:** Measured wall-clock converts to billable hours by **truncation to milli-hours** at PRECISION=6 ($0.0003/hr → 1 milli-hour = 0.3 minions); sub-second windows bill as 0 — requestor-favorable, nodes absorb sub-second losses
- **D-03:** When the deadline fires mid-generation, billing **cancels at deadline** — generation is cancelled immediately (via the Phase 3 cancel mechanism), the subtask publishes `finish_reason: cancelled` with measured counts, and unused escrow refunds. Hard budget enforcement at the three-clock deadline; never bill past the declared maximum (FUND-03 terminal-not-regrabbed semantics)

### Schema Shape & Defaults
- **D-04:** **Default-fill** — everything optional has a default; minimal job JSON = `job_type` + `elms[]` with manifest+input only. Defaults: `funding.maximum_processing_hours` = **1.0h** (covers cold-cache Qwen-0.5B download plus generation; escrow at hold = 300 minions ≈ $0.0003), generation settings default to safe values (temperature=1.0, top_p=1.0), `validation` defaults to `none`
- **D-05:** **Out-of-range values reject at parse** with a structured error — never clamp. Bounds: temperature ∈ [0,2], top_p ∈ (0,1], max_output_tokens > 0 (upper bound per model cap), hours > 0 with a sane cap (e.g. 24h). Deterministic funding wants deterministic jobs
- **D-06:** **No new version field** — reuse the existing quicktype `SgnsProcessing` root fields: `gnus_spec_version` (double, quicktype-constrained ==1) governs schema evolution; unknown/unsupported spec versions already fail quicktype's constraint check at parse. The ELM block rides beside `passes[]` under the same root
- **D-07:** Duplicate `work_item_id`, missing/unknown fields with no default, and unknown validation modes reject at parse with a structured error (SC-1; validated at parse time, never mid-subtask)

### Three-Clock Derivation
- **D-08:** Margin formula: **deadline = `maximum_processing_hours` exactly** (the declared budget IS the deadline — no inflation of escrow beyond the declared max); **subtask lock timeout = deadline + fixed grace** (e.g. +60s) so a finishing-at-the-bell subtask can still publish before its lock expires. All three clocks share one derivation source
- **D-09:** The single three-clock derivation lives on the **SuperGenius side** — a helper near `processing_tasksplit_elm` (or a small clocks utility). Justification: the timeout field is a SuperGenius queue concept (`SGProcessing.proto:61` `processing_timeout_length`, wired via `SetProcessingTimeout()` at enqueue — currently zero production callers) and only SuperGenius consumes it today
- **D-10:** The deadline is **per-subtask from its own grab**: deadline = grab_time + maximum_processing_hours, lock = deadline + grace. Every work item gets the full budget regardless of siblings — consistent with sum-of-per-subtask billing (D-01) and cancel-at-deadline (D-03). A subtask holding a valid lock at t>60s is NOT re-grabbed (SC-3)

### ELM Validation Finalization
- **D-11:** For `validation: none` (v1.0 default), an ELM subtask finalizes on **first accepted result** — the existing single-result path; no cross-subtask comparison, no redundant execution. The hash comparison in `ValidateResults` is skipped via a job-type/flag check at the validation call site; the queue completes on result receipt
- **D-12:** The validation-mode gate reads from the **job schema at the call site** — the worker/validation code reads the mode from the re-created `ProcessingManager` (which parsed `Task.json_data`). JSON shape does the routing — same pattern as the rest of the architecture; no subtask-carried flags
- **D-13:** The schema carries the **full enum `none|exact|redundant`**, but v1.0 implements `none` only — `exact`/`redundant` reject at parse as unimplemented. Schema is complete; implementation is honest; no dead code paths

### Claude's Discretion
- Exact structured-error format/fields for parse rejections (follow existing quicktype/`CheckConstraint` conventions where possible)
- The precise lock-grace constant value (~60s suggested) — planner may tune with a floor ensuring publication latency is always covered
- The sane upper cap for `maximum_processing_hours` (suggested 24h) and upper bound defaults for `max_output_tokens`
- Where the ELM block sits in the quicktype JSON schema file (beside `passes[]`, new top-level section) — follow SCHEMA-01..05 zero-hand-edit norms
- Unit-test structure for the parse-rejection matrix and three-clock derivation

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Workstream research (verified against `dev_elmruntime` branches of both repos)
- `.planning/workstreams/elmbridge/research/SUMMARY.md` — Phase 1 scope, research flags (escrow wall-clock verification, validation finalization design), gaps to address
- `.planning/workstreams/elmbridge/research/ARCHITECTURE.md` — job-type routing pattern (`ProcessImage` branch sketch), component responsibilities, project structure, 13 integration points
- `.planning/workstreams/elmbridge/research/FEATURES.md` — job-model JSON shape (§A), funding (§F), anti-features table (binding scope corrections)
- `.planning/workstreams/elmbridge/research/PITFALLS.md` — Pitfall 2 (validation regime, P1 schema decision), Pitfall 3 (15s lock timeout, P1 wiring), Pitfall 4 (hours-based cost chain), Pitfall 10 (three-clock rule), 12 (schema fields), 11 (count fields)

### Planning artifacts
- `.planning/workstreams/elmbridge/REQUIREMENTS.md` — JOB-01, JOB-03, FUND-01..03 definitions; Out of Scope list (binding)
- `.planning/workstreams/elmbridge/ROADMAP.md` — Phase 1 success criteria (SC-1..SC-5) and notes
- `.planning/workstreams/elmbridge/STATE.md` — D-001..D-004 prior decisions (build order, fork patches approved, zero new deps, scope discipline)

### Code anchors (verified line-level integration points)
- `SuperGenius/src/account/GeniusNode.cpp` — `ProcessImage` (~2257, job entry point + branch site), `GetProcessCost` (~2388, byte-based branch point), `HoldEscrow` call (~2320), `CreateEscrowInfoCRDTTransaction`
- `SuperGenius/src/processing/processing_subtask_queue_manager.cpp:21` — 15s default `m_processingTimeout`; `SetProcessingTimeout()` has zero production callers (Pitfall 3)
- `SuperGenius/SGProcessingManager/generated/SgnsProcessing.hpp` — quicktype root schema: `gnus_spec_version` (==1 constraint), `version` (semver) — D-06 basis
- `SuperGenius/SGProcessingManager/src/processingbase/ProcessingManager.cpp` — `Create` (~419) parse path to extend
- `SuperGenius/src/account/TokenAmount.cpp:65` — `CalculateCostMinions` (existing byte-based cost for contrast; ELM branch bypasses)
- `SuperGenius/.planning/notes/ELM-bridging-gaps.md` — manifest shape draft, upstream scope corrections (ELM-01..ELM-09)
- `SuperGenius/.planning/REQUIREMENTS.md` — ELM-01..ELM-09 upstream requirement definitions

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **Quicktype pipeline** (`gnus-processing-schema.json` → `generated/`): schema changes regenerate; `CheckConstraint` gives structured constraint errors for free (bounds, patterns) — D-05/D-06 ride it
- **`SgnsProcessing` root**: `gnus_spec_version`, `metadata` map, `parameters[]`, `passes[]` — ELM block joins these as a sibling section
- **Escrow plumbing** (`HoldEscrow`/`AsyncPayEscrow`/`CreateEscrowInfoCRDTTransaction`): mechanics unchanged — only the amount computation and settlement measurement change
- **`TokenAmount`/`ScaledInteger` (PRECISION=6)**: minions arithmetic for the hours × rate conversion
- **`SetProcessingTimeout()` / `processing_timeout_length`**: the per-job lock-timeout wire already exists but is unwired — D-09 wires it at ELM enqueue

### Established Patterns
- **Job-type routing via JSON sniffing** at exactly two call sites (splitter + cost) — existing chunk path stays byte-for-byte unchanged
- **Submodule-first landing**: schema lands in SGProcessingManager; SuperGenius branch follows the pointer bump (innermost-first commit discipline)
- **Zero hand-edits to `generated/`** (SCHEMA-01..05 norm from sgproc-render)

### Integration Points
- `GeniusNode::ProcessImage` — `job_type` sniff → ELM cost branch + ELM validation branch (splitter itself is Phase 4)
- `ProcessingManager::Create`/`Init` — ELM schema parse/validation (reject-at-parse matrix)
- Subtask enqueue path — `SetProcessingTimeout(derived)` wiring (D-08/D-09/D-10)
- Validation call site (`ValidateResults` caller in the subtask queue completion path) — first-result-accept gate (D-11/D-12)

</code_context>

<specifics>
## Specific Ideas

- User corrected the version-field question by pointing at the existing quicktype schema's version fields — downstream agents should verify schema field reuse before adding any new top-level versioning (D-06)
- Escrow rate recording: the USD→GNUS rate used at hold time must be recorded in the escrow transaction (locked by roadmap SC-2) — settlement disputes when the price moves are the failure mode this prevents
- Research flags carried into planning (from SUMMARY "Gaps"): (a) verify escrow wall-clock accounting measures from subtask grab (download included) — don't assume; if compute-only, fetch must be explicitly included; (b) `gen_seq_len` early-stop accounting is a Phase 3 flag, not Phase 1

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 1-ELM Job Model & Funding*
*Context gathered: 2026-09-09*
