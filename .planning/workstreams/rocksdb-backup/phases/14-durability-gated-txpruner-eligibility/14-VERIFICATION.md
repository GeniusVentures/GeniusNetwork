---
phase: 14-durability-gated-txpruner-eligibility
verified: 2026-11-17
verifier: inline (Copilot sequential mode, gsd-verifier contract)
goal: |
  Durability-gated TxPruner eligibility: the cold-durability admission
  conjunct at TxPruner::RunCycle's group filter + the in-compose re-check
  (guard 5) — a Light+cold node can never erase hot data that is not
  evidence-Durable, deferrals are counters (never failure reasons), the
  evaluator stays contractually pure, and cold-off nodes behave
  byte-identically.
requirements: [PRUNE-01, PRUNE-02, PRUNE-03]
status: passed
score: 12/12 must-haves verified
human_verification: []
gaps_found: false
---

# Phase 14 Verification — Durability-Gated TxPruner Eligibility

**Verdict: PASSED — all three requirements verified against the codebase; no gaps; no pending human-verification items.**

## Goal-backward check

The phase's reason to exist was closing the unsafe posture "a Light+cold node erases hot data that is not evidence-Durable." After plan 14-01 that posture is impossible on the admission path (exact-Durable-only permit, whole-group deferral); after 14-02 it is impossible even under an induced mid-cycle journal regression (in-compose re-check under the compose lock, red→green proven); 14-03 sealed the evidence (five-state matrix, edges, composition, Tier-1 contract). Every claim below was re-checked against the tree at SuperGenius `095c8c502`.

## Must-have verification

### Plan 14-01 (SC1 core + SC4 vacuous branch)

| Must-have | Evidence | Status |
|-----------|----------|--------|
| Cold-enabled Light node admits/erases only evidence-Durable groups; Pending defers whole-group into `cold_deferred_groups`; never errors/WARN-failure/permanent-stop | `TxPruner.cpp` `ColdGateAdmitsGroup` + group filter; `Gate_DurableAdmitsAndErases`, `Gate_PendingDefersWholeGroupAsCounter` green | PASS |
| SC4 vacuous branch: cold-off nodes byte-identical, `NodeType::Light` check untouched, no new config knob | `HasColdStorage()` vacuous admit; `Gate_ColdDisabledNodeVacuousBranch` green; diff shows no `TxPruner::New` change | PASS |
| Deferrals surface ONLY as counters, both in the INFO summary, "not measured until Phase 20" clause intact | INFO line extension verified in source + logs (`cold_deferred={}, cold_unreadable={}`) | PASS |
| Shutdown safety: no shutdown clause in `HasColdStorage()` (Pitfall 8) | Source-verified with rationale comment | PASS |
| PRUNE-03 placement: filter-local named conjunct; `PruneEligibility.{hpp,cpp}` byte-identical to 2af184fa1 | `git diff --exit-code` exit 0 (re-run at phase close) | PASS |

### Plan 14-02 (SC2 in-compose re-check)

| Must-have | Evidence | Status |
|-----------|----------|--------|
| Induced regression (Durable→Accepted / Durable→NoRecord) between admission and erase is REFUSED: value survives, no marker, `cold_deferred_groups` grows, `errors` does not — red-first | `InducedRegressionBetweenAdmissionAndComposeIsRefused/{DurableToAccepted,DurableToNoRecord}` green; RED evidence recorded verbatim in 14-02-SUMMARY (guard-less run: erased=1, value destroyed, marker staged) | PASS |
| Probe position = TxPruner step 5, NEVER GlobalDB erase-hook steps 2/3 (Pitfall 2); monotonicity/Phase-16 two-layer story in code | `kInterruptAfterColdGate = 5` firing after admission before erase loop; guard-5 comment block carries the two-layer story; test header states the discipline | PASS |
| No re-check-to-commit window; no new lock edges (Pitfall 3) | Guard 5 inside MakeComposeLock after guard 4 before staging; only accessor calls; `globaldb_integration_test` + `tx_pruner_test` green | PASS |
| Distinct refusal end-to-end: `Error::COLD_NOT_DURABLE` → verbatim passthrough → TxPruner counter mapping | Enum value + BOOST_OUTCOME_TRY at TransactionManager.cpp:4755 + mapping branch; call-site audit recorded (1 production caller, fail-correct) | PASS |

### Plan 14-03 (matrix + composition + D-09)

| Must-have | Evidence | Status |
|-----------|----------|--------|
| Five states: NoRecord/Accepted via direct CF seeding (D-02 defer-forever, never permanent-stop); Pending/Durable (14-01); Unreadable real-fault at bridge AND gate level (dedicated counter + WARN + cycle continues) | `SeedVariants/{NoRecord,Accepted,GarbageStateByte,GarbageVersionByte}` + `UnreadableBridge_MapsRealFault` + `Gate_UnreadableDefersLoudlyAndCycleCompletes` green (WARN observed via counting sink: exactly 1 per group per cycle) | PASS |
| Adjacency: garbage values decode Pending and defer (never Durable/Unreadable counters) | Both garbage variants assert `cold_deferred_groups==1`, `cold_unreadable_groups==0` | PASS |
| Empty edge + ordering edge | `Gate_EmptyCycleMovesNoCounters` + `Gate_OrderingDeferredLeaderDoesNotBlockSurvivor` green (follower erases same-cycle) | PASS |
| SC3: erasable×Durable→erased; erasable×Pending→deferred; NON-erasable×Durable→not erased + zero counter motion (no widening); no-cold×erasable→erased; AND read directly (Evaluate + journal) | Crossing legs green incl. `Composition_NonErasableTimesDurableNeverErases` (direct-Evaluate in-test asserts ineligible + zero block reports) | PASS |
| D-08c live smoke exists, env-gated, loud-skip proven, no Tier1 label; posture recorded | `cold_prune_live_smoke_test` — labelled SKIP captured verbatim (env var + runbook + community-binary rule + deterministic stand-in); LABELS "Tier3"; `tier1_static_audit` green | PASS (live leg runbook-deferred — the plan's sanctioned posture; D-08c never marked satisfied by silence) |
| D-09: full Tier-1 lane green incl. both new suites; ten-suite regression net zero-regression | `ctest -L Tier1` 14/14; net 10/10 (prune_eligibility, tx_pruner, node_startup, crdt_test[crdt_erase], globaldb_integration_test[globaldb_erase], fallback, durability, gc, gc_retrievability, resurrection) | PASS |

## Requirement traceability

| ID | Description | Plans | Verified |
|----|-------------|-------|----------|
| PRUNE-01 | Cold-enabled TxPruner erases only when constituent blocks are Durable; others defer loudly (fail closed) | 14-01, 14-03 | YES — 5-state matrix + edges + counters + WARN, Tier-1 green |
| PRUNE-02 | Gate re-checks evidence at erase-commit under the compose lock; TOCTOU cannot enable a destroying erase | 14-02, 14-03 | YES — guard 5 + red→green counter-test on both regression vectors |
| PRUNE-03 | Gate injected at the cycle filter; evaluator stays contractually pure; composes with develop's evaluator | 14-01, 14-03 | YES — named conjunct in filter; purity git gate exit 0; crossing legs prove AND-composition without widening |

REQUIREMENTS.md marks all three Complete (checkbox + traceability), released by the shared-ID gate after 14-03's summary.

## Gaps

None. The one environment-bound deferral (D-08c live-wire execution) is the plan's explicitly sanctioned runbook-deferred posture with the deterministic Tier-1 stand-in green — recorded in 14-03-SUMMARY, not a gap.

## Verification commands (reproducible)

```
ctest --test-dir SuperGenius/build/Windows/Release -C Release -R "cold_prune_gate_test|cold_prune_toctou_test"   # 15 legs
ctest --test-dir SuperGenius/build/Windows/Release -C Release -L Tier1                                          # 14/14
ctest --test-dir SuperGenius/build/Windows/Release -C Release -R "<ten-suite net pattern>"                      # 10/10
git -C SuperGenius diff --exit-code 2af184fa1 -- src/transaction/PruneEligibility.hpp src/transaction/PruneEligibility.cpp  # 0
```
