---
phase: 14-durability-gated-txpruner-eligibility
reviewed: 2026-11-17
reviewer: inline (Copilot sequential mode, gsd-code-review contract)
scope: |
  Production diff SuperGenius 2af184fa1..095c8c502 (4 files, +313/-22):
  src/transaction/TxPruner.cpp, src/transaction/TxPruner.hpp,
  src/crdt/globaldb/globaldb.cpp, src/crdt/globaldb/globaldb.hpp.
  Test binaries (cold_prune_gate_test, cold_prune_toctou_test,
  cold_prune_live_smoke_test) reviewed as evidence, not production surface.
method: |
  Full-diff read of both implementation TUs + headers; threat-register
  cross-check (T-14-01..T-14-07); behavior verified against 27 green test
  executions this phase (13 gate legs, 2 TOCTOU parameterizations,
  Tier-1 lane 14/14, regression net 10/10); evaluator purity git gate exit 0.
verdict: PASS (advisory; no blocking findings)
severity_counts:
  critical: 0
  major: 0
  minor: 2
  info: 1
---

# Phase 14 Code Review — Durability-Gated TxPruner Eligibility

## Findings

### MIN-1 — Unsynchonized TEST-ONLY static hook reads (established seam precedent)
- **File:** `src/crdt/globaldb/globaldb.cpp` (`GetColdUploadState` consult of `cold_upload_state_hook_for_test_`)
- **Issue:** The process-global hook is read without synchronization; `SetColdUploadStateHookForTest` mutates it from the arming thread while another thread could concurrently call `GetColdUploadState`.
- **Assessment:** Production never arms the hook (inert `nullptr`), tests arm and consume on the same thread, and the identical posture is the established precedent of `erase_interrupt_hook_for_test_` beside it. Not a production risk.
- **Recommendation:** none required; a comment already carries the PRODUCTION-MUST-NEVER-CALL discipline.

### MIN-2 — Continuation-line indent nit in the new debug log
- **File:** `src/transaction/TxPruner.cpp` (`logger_->debug( "Prune erase deferred for tx {}...` continuation argument line)
- **Issue:** One-space indentation drift on the continuation line relative to the file's alignment convention.
- **Assessment:** Cosmetic; compiles clean; no functional impact.

### INFO-1 — Guard 5 refusal log level is WARN (deferral, not anomaly)
- **File:** `src/crdt/globaldb/globaldb.cpp` (guard 5's `m_logger->warn`)
- **Issue:** The plan allowed "warn or info"; WARN was chosen. A persistently non-Durable cold node will emit one WARN per refused erase per cycle.
- **Assessment:** Deliberate (D-03's loud-deferral letter at the commit boundary); the per-cycle counter summary remains the operator surface. Revisit only if cycle-frequency WARNs prove noisy in operation.

## Verified strengths
- Exact-equality Durable-only permit with the default-arm defer (an unknown future enum value can never admit — T-14-01); unparseable CIDs fail closed.
- Whole-group deferral via the `cold_gate_deferred` set — the gate is consulted exactly once per group, no double-counting, no per-tx gating drift (Pitfall 4).
- Guard 5 inside the MakeComposeLock critical section after guard 4, before staging; only lifecycle-scoped accessor reads — no new lock edges (Pitfall 3); distinct `COLD_NOT_DURABLE` refusal mapped to `cold_deferred_groups` ahead of the generic errors branch (Pitfall 1), proven by the counter-test's `errors == 0` assertion.
- `HasColdStorage()` deliberately shutdown-clause-free (Pitfall 8) with the rationale in code.
- `PruneEligibility.{hpp,cpp}` byte-identical to 2af184fa1 (purity gate, re-run at phase close).
- Single production `EraseEntry` call site (both erase drivers) audited — fail-correct posture on cold-enabled nodes, vacuous on cold-off.
