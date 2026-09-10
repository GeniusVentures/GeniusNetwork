# Phase 1: ELM Job Model & Funding - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-09-09
**Phase:** 1-ELM Job Model & Funding
**Areas discussed:** Escrow & settlement semantics, Schema shape & defaults, Three-clock derivation, ELM validation finalization

---

## Escrow & Settlement Semantics

### Billable time aggregation

| Option | Description | Selected |
|--------|-------------|----------|
| Sum of per-subtask | Each subtask bills grab→publication independently; concurrent work items each bill their window — requestor pays for compute used, matching the per-work-item envelope shape | ✓ |
| Job elapsed wall-clock | Bill first-grab→last-publication elapsed time; parallelism free for requestor but under-bills the node when work items run concurrently | |
| Sum, download deduped | Sum of per-subtask but download billed once per model — deduped across subtasks sharing the same manifest hash on the same node | |

**User's choice:** Sum of per-subtask
**Notes:** Single node runs subtasks on parallel worker threads; sum-of-subtasks means concurrent work items each bill their full window — accepted as correct (pay for compute used).

### Settlement rounding

| Option | Description | Selected |
|--------|-------------|----------|
| Truncate to hours | Milli-hour truncation at PRECISION=6; sub-second windows bill as 0; requestor-favorable, nodes absorb sub-second losses | ✓ |
| Floor at 0.001h | Any nonzero window bills minimum 1 minion (~3.6s); protects nodes from many tiny subtasks | |
| Round to 0.001h | Round-half-up to 3 decimals of an hour; splits the difference | |

**User's choice:** Truncate to hours
**Notes:** Sub-minute windows are real (cached model + short generation).

### Overtime billing

| Option | Description | Selected |
|--------|-------------|----------|
| Bill past max, escrow caps | Wall-clock accrues past declared max until finish or lock expiry; escrow caps payment; node never unpaid for executed work | |
| Cancel at deadline | Deadline cancels generation immediately (Phase 3 cancel mechanism), subtask publishes finish_reason=cancelled with measured counts, unused escrow refunds — hard budget enforcement | ✓ |
| Soft deadline | Deadline advisory; generation runs to completion, full time billed, potentially exceeding escrow (node eats difference) | |

**User's choice:** Cancel at deadline
**Notes:** Matches FUND-03 terminal-not-regrabbed semantics.

---

## Schema Shape & Defaults

### Required vs defaulted

| Option | Description | Selected |
|--------|-------------|----------|
| Default-fill | Everything optional has a default (funding 1.0h, generation settings safe values, validation none); minimal job JSON = job_type + elms[] with manifest+input | ✓ |
| Strict-required | Funding, all generation settings, validation mode must be explicit; verbose but no hidden behavior | |
| Hybrid | Funding + validation required (money/correctness), generation settings defaulted (execution) | |

**User's choice:** Default-fill
**Notes:** Malformed inputs (duplicate work_item_id, bad manifest hash) reject either way.

### Default maximum_processing_hours

| Option | Description | Selected |
|--------|-------------|----------|
| 1.0 hour | Covers cold-cache Qwen-0.5B download (~300MB IPFS) plus generation; escrow at hold = 300 minions | ✓ |
| 0.25 hour | Tighter cap, faster BUDGET_EXCEEDED on runaway jobs; slow first download could hit deadline on cold node | |
| Required, no default | Revisit previous answer: funding always explicit | |

**User's choice:** 1.0 hour

### Out-of-range handling

| Option | Description | Selected |
|--------|-------------|----------|
| Reject at parse | Bounds violations fail at parse with structured error; deterministic funding wants deterministic jobs — reject, don't clamp | ✓ |
| Clamp with warning | Out-of-range values clamp to nearest bound with warning logged; forgiving but silent behavior change | |

**User's choice:** Reject at parse

### Schema versioning

| Option | Description | Selected |
|--------|-------------|----------|
| Include version field | New `version` field beside job_type; unknown major versions reject at parse | |
| No version field | job_type alone; evolve by adding optional fields only via quicktype regen | |

**User's choice:** (free-text) "Our json schema (quicktype generates c++ for sgprocessingmanager) already has a version field, no?"
**Notes:** Claude verified against `SuperGenius/SGProcessingManager/generated/SgnsProcessing.hpp` — the root schema already carries `gnus_spec_version` (double, quicktype-constrained ==1) and `version` (semver string). Decision: reuse existing fields; no new version field; unknown spec versions already fail quicktype's constraint check.

---

## Three-Clock Derivation

### Margin formula

| Option | Description | Selected |
|--------|-------------|----------|
| Deadline=hours, lock+grace | Deadline = maximum_processing_hours exactly; lock timeout = deadline + fixed grace (~60s) so a finishing-at-the-bell subtask can still publish | ✓ |
| Uniform ×1.5 | All three clocks = hours × 1.5; generous but inflates escrow beyond declared max | |
| Proportional + fixed | Deadline = hours + 10% + 30s; lock = deadline + 60s; scales with job size, fixed floor for tiny jobs | |

**User's choice:** Deadline=hours, lock+grace

### Derivation home

| Option | Description | Selected |
|--------|-------------|----------|
| SGProcessingManager | One function next to the schema; SuperGenius calls it at enqueue; schema+clocks version together | |
| SuperGenius side | Helper in SuperGenius (near processing_tasksplit_elm); timeout field is a SuperGenius queue concept (SGProcessing.proto:61), only SuperGenius consumes it today | ✓ |
| Inline at call sites | Duplicate small formula at each call site; no new dependency edge but drift risk | |

**User's choice:** SuperGenius side

### Deadline scope

| Option | Description | Selected |
|--------|-------------|----------|
| Per-subtask full budget | deadline = grab_time + hours, lock = deadline + grace; every work item gets full budget regardless of siblings | ✓ |
| Job-level absolute | Job deadline = enqueue + hours; all subtasks derive from same instant; late grabbers get shortened window | |

**User's choice:** Per-subtask full budget
**Notes:** Matches sum-of-per-subtask billing and cancel-at-deadline.

---

## ELM Validation Finalization

### Finalization mechanism (validation: none)

| Option | Description | Selected |
|--------|-------------|----------|
| First-result accept | Finalize on first accepted result (existing single-result path); skip hash comparison via job-type/flag check at validation call site | ✓ |
| Notional chunk hash | Single notional chunk whose hash is the envelope's own sha256; reuses chunk machinery but hash is self-referential | |
| All three modes now | exact = requestor-supplied expected hash; redundant = second execution compare; more code, guards replay | |

**User's choice:** First-result accept

### Gate location

| Option | Description | Selected |
|--------|-------------|----------|
| Schema-flag at call site | Validation-mode field in ELM job JSON; call site reads from re-created ProcessingManager (parsed Task.json_data); JSON shape does the routing | ✓ |
| Subtask-carried flag | SubTask.json_data gains validation hint written by splitter; validation stays job-type-blind | |

**User's choice:** Schema-flag at call site

### Enum completeness

| Option | Description | Selected |
|--------|-------------|----------|
| Enum full, implement none | Schema carries none|exact|redundant; v1.0 implements none only; exact/redundant reject at parse as unimplemented | ✓ |
| None only in schema | Only none in v1.0; other values added later via quicktype regen | |

**User's choice:** Enum full, implement none

---

## Claude's Discretion

- Structured-error format for parse rejections (follow quicktype/CheckConstraint conventions)
- Lock-grace constant (~60s suggested; floor must cover publication latency)
- Upper cap for maximum_processing_hours (suggested 24h) and max_output_tokens bounds
- ELM block placement in quicktype schema file (beside passes[])
- Unit-test structure for parse-rejection matrix and three-clock derivation

## Deferred Ideas

None — discussion stayed within phase scope.
