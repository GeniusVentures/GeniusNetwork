# Phase 14: Durability-Gated TxPruner Eligibility - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-11-16
**Phase:** 14-Durability-Gated TxPruner Eligibility
**Areas discussed:** Constituent-block scope, GATE-01 widening knob, TOCTOU re-check strictness, Test evidence posture

---

## Constituent-block scope

| Option | Description | Selected |
|--------|-------------|----------|
| Removal-set rule (recommended) | Gate exactly the CIDs whose bytes the erase physically deletes — today the group's single delta-block CID. Researcher verifies EraseEntry's removal set stays single-CID on the merged line. 1 journal read per group; SC1 interpreted as 'constituent = removal set'. | ✓ |
| All-referenced-blocks rule | Gate every block the tx references (defense-in-depth) even though only the delta's bytes are deleted. Extra journal reads; risks deferring forever on referenced blocks that never spill — vacuous on current code. | |

**User's choice:** Removal-set rule
**Notes:** Code scout during discussion showed `EraseTransactionEntryWithMarker` resolves each tx to exactly ONE CID (tx→CID map) and `EraseEntry` deletes that block's bytes + CRDT entries + marker atomically — so the removal set is single-CID today, making the two options converge; the ruling locks the interpretation for the audit.

### NoRecord posture

| Option | Description | Selected |
|--------|-------------|----------|
| Defer-forever accepted (recommended) | NoRecord (never spilled OR journal deleted by GC disposal) → group deferred, re-evaluated next cycle. Under-prune is the accepted safe direction; cross-marker skip stays Phase 16 scope per research. | ✓ |
| Distinguish disposed now | Distinguish not-yet-spilled from GC-disposed NOW (consult disposed markers in the gate) — pulls Phase 16's optional cross-marker item into this phase. | |

**User's choice:** Defer-forever accepted

### Unreadable loudness (MI-02)

| Option | Description | Selected |
|--------|-------------|----------|
| Dedicated counter + WARN (recommended) | A dedicated counter (cold_unreadable_groups) alongside cold_deferred_groups, plus a WARN line. Journal corruption is anomalous — distinct visibility costs nothing and satisfies MI-02. | ✓ |
| Shared counter, WARN only | Unreadable increments the same cold_deferred_groups counter; loudness is just the log level. Corruption indistinguishable from slow spill in stats. | |
| Permanent-stop error | Treat Unreadable as permanent-stop class (like invalid_argument Evaluate failures) — halts the pruner service. A single corrupt record bricks pruning entirely. | |

**User's choice:** Dedicated counter + WARN

---

## GATE-01 widening knob

| Option | Description | Selected |
|--------|-------------|----------|
| Automatic, no knob (recommended) | Gate activates automatically whenever a Light node has cold enabled — Light+cold today is the unsafe posture this phase fixes; no opt-in, no new config surface, NodeType::Light-only untouched (Pitfall 3 moot). | ✓ |
| Opt-in knob, default off | A named config knob (GATE-06 shape) defaults OFF — Light+cold does not prune until the operator opts in. Silently disables pruning for existing Light+cold nodes; adds config surface Phase 18 must interlock with. | |
| Knob, default on | Knob exists but defaults ON (escape hatch). Same automatic safety plus a config lever — but a knob that can be turned off can also mask the gate. | |

**User's choice:** Automatic, no knob

### Policy home

| Option | Description | Selected |
|--------|-------------|----------|
| Named conjunct in factory (recommended) | Activation ruling lives as a named conjunct inside the existing fail-closed factory + per-cycle evaluator construction — evaluator stays pure, wiring stays the single policy owner. | ✓ |
| Policy matrix in evaluator | Declarative policy matrix (NodeType × cold-config → prunable) consulted by factory and PruneEligibility construction — touches the evaluator construction contract this phase doesn't otherwise change. | |
| Agent discretion | Lock only the semantics (Light-only + automatic gate), let researcher pick the mechanical home. | |

**User's choice:** Named conjunct in factory

---

## TOCTOU re-check strictness

| Option | Description | Selected |
|--------|-------------|----------|
| In-compose re-check (recommended) | Journal read happens inside the same critical section that composes/commits the destructive WriteBatch (gate hook in EraseEntry's compose path or equivalent lock composition) — no window between re-check and commit. Matches SC2's letter. | ✓ |
| Pre-batch under cold mutex | Re-read under cold_store_mutex_ immediately before composing each batch — mirrors GC's mark-time read; a window remains unless mutexes are composed; Phase 16 Interaction-C may force rework. | |
| Group-take-time only | Re-check once when the group enters the erase loop — cheapest, but outside the compose path entirely; weakest fit to SC2. | |

**User's choice:** In-compose re-check
**Notes:** Exact mechanism (hook vs lock-order) left to research/planning; must not contradict Phase 16's Interaction-C mutual-exclusion ruling.

### Counter-test scope

| Option | Description | Selected |
|--------|-------------|----------|
| Induced regression, red-first (recommended) | Test flips journal Durable→Accepted/NoRecord between gate admission and erase-commit via the existing interrupt-seam pattern (new interrupt point), red-first — proves the in-compose re-check reads fresh state. SC2's letter requires induced regression. | ✓ |
| Staleness-only + monotonicity doc | Counter-test proves evaluator-time staleness only; monotonicity research documents Durable as terminal. Lighter test, leaves the re-check unproven against the exact race SC2 names. | |

**User's choice:** Induced regression, red-first

---

## Test evidence posture

| Option | Description | Selected |
|--------|-------------|----------|
| Hybrid: injection + 1 live E2E (recommended) | Journal-injection state matrix (pre-seed journal CF into each of 5 states against real GlobalDB — deterministic, no live remote, Unreadable trivially inducible) + red-first TOCTOU counter-test + one dev-gated live-stack E2E smoke proving real drainer transitions pass the gate. | ✓ |
| Live-stack only | All gate tests ride the live v1.1 fixture kit. Most realistic; Pending/Accepted timing flaky, Unreadable needs corruption injection, nothing lands in fresh-clone CI. | |
| Injection only | No live leg this phase — live proof rides Phase 15's evidence suites. Fastest; gate ships without ever being observed against a real drainer transition. | |

**User's choice:** Hybrid: injection + 1 live E2E

### CI tier placement

| Option | Description | Selected |
|--------|-------------|----------|
| Tier-1 now for deterministic suite (recommended) | Journal-injection suite + TOCTOU counter-test enter CI Tier-1 now (fresh-clone-safe: real RocksDB, no services; v1.1 already runs cold-storage Tier-1 suites). Live E2E smoke stays dev-gated Tier-2/3. | ✓ |
| Tier-2/local-first, promote at 19 | Everything local/dev-gated this phase; promotion at Phase 19's capstone. Most conservative (extends Phase 13 D-10 posture), but the gate's core invariant ships unguarded in CI for 5 phases. | |
| Researcher decides | Rule per-suite based on what v1.1 Tier-1 cold suites actually construct and what fresh-clone CI tolerates. | |

**User's choice:** Tier-1 now for deterministic suite

---

## The Agent's Discretion

- Exact in-compose mechanism (gate hook inside `EraseEntry` vs TxPruner-side lock composition)
- Interrupt-point naming/placement for the TOCTOU counter-test
- Per-tx vs short-circuited per-group in-compose re-check execution
- Journal pre-seeding test helpers and fixture reuse specifics from v1.1 GC/cold suites
- Light+cold posture log line; gate counters in the per-cycle INFO summary
- Additional PruneCycleStats counter naming beyond cold_deferred_groups / cold_unreadable_groups
- Composition-test shape proving the cold conjunct composes with the evaluator (SC3)

## Deferred Ideas

- Vulkan capability-probe todo — keyword-only match, zero topical overlap; not folded (same ruling as Phase 13)
