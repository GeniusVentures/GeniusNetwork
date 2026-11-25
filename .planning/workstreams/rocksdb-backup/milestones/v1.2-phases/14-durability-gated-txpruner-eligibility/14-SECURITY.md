---
phase: "14"
slug: "durability-gated-txpruner-eligibility"
status: verified
# threats_open = count of OPEN threats at or above workflow.security_block_on severity (the blocking gate)
threats_open: 0
asvs_level: 1
created: "2026-11-25"
---

# Phase 14 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.

> Input state B (no prior SECURITY.md; created retroactively from PLAN registers + SUMMARY evidence + the phase's own VERIFICATION.md).
> L1 short-circuit applied: threats_open 0 · register authored at plan time · asvs_level 1 (no auditor spawn required).

---

## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| journal evidence -> erase admission | the gate's permit decision crosses from cold-store evidence (RocksDB journal CF) into a destructive hot-store decision — the exact boundary AF-5 attacked |
| GlobalDB lifecycle -> TxPruner cycle | a cycle racing shutdown reads through lifecycle_mutex_-protected accessors; wrong tier-presence logic flips the gate open during teardown |
| evaluation-time evidence -> commit-time destruction | the destructive WriteBatch commit is the trust boundary; evidence older than the commit must not authorize it (PRUNE-02's whole scope) |
| test injection seam -> production read path | the TEST-ONLY override sits inside GetColdUploadState — production must never arm it, and the hook must be inert when unset |
| seeded journal bytes -> gate verdict | the seeding machinery writes the coldstore journal directly — it must model only REACHABLE states (the adjacency leg proves unreachable decodings defer) and never fabricate a permit |
| env-gated live wire -> CI lane | the live smoke touches a real network service; the env gate + loud-skip is the boundary keeping the CI lane hermetic (D-09) |

---

## Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation | Status |
|-----------|----------|-----------|----------|-------------|------------|--------|
| T-14-01 | Tampering | cold conjunct admission logic (TxPruner.cpp group filter) | high | mitigate | Exact-equality Durable-only permit; every other enum value AND the default case defer — an unknown future enum value can never admit. Evidence: verifier 2026-11-17 — Gate_DurableAdmitsAndErases + Gate_PendingDefersWholeGroupAsCounter green in the Tier-1 lane | closed |
| T-14-02 | Tampering | GlobalDB::HasColdStorage() (SC4 tier-presence signal) | high | mitigate | Computed as cold_manager_ != nullptr under lifecycle_mutex_; never inferred from NoRecord states; no shutdown clause so teardown flows to NoRecord->defer. Evidence: Gate_ColdDisabledNodeVacuousBranch green; source-verified with rationale comment (14-VERIFICATION, Plan 14-01 rows 2/4) | closed |
| T-14-03 | Denial of Service | deferral accounting in RunCycle | medium | mitigate | Deferrals are counters with whole-group skip and continue-never-abort; a persistently non-Durable group can never brick the cycle. Evidence: LEG 2 second-cycle re-evaluation proves liveness; counters verified in the INFO summary (cold_deferred={}, cold_unreadable={}) | closed |
| T-14-04 | Tampering | EraseEntry compose critical section (guard 5) | critical | mitigate | Re-check inside the same MakeComposeLock section that spans guard->staging->commit; only-Durable permit. Evidence: InducedRegressionBetweenAdmissionAndComposeIsRefused/{DurableToAccepted,DurableToNoRecord} green, red-first (guard-less run: erased=1, value destroyed, marker staged — recorded verbatim in 14-02-SUMMARY) | closed |
| T-14-05 | Denial of Service | refusal mapping in TxPruner per-tx path | medium | mitigate | Distinct Error::COLD_NOT_DURABLE mapped to cold_deferred_groups — never stats.errors, never the failure WARN. Evidence: enum value + BOOST_OUTCOME_TRY at TransactionManager.cpp:4755 + mapping branch; counter-test's errors==0 assertion (14-VERIFICATION, Plan 14-02 row 4) | closed |
| T-14-06 | Tampering | lock-order of the in-compose journal read | high | mitigate | Guard 5 calls ONLY HasColdStorage/GetColdUploadState (sequential lifecycle_mutex_ reads over the pre-existing chain); no datastore re-entry; no new edge. Evidence: guard 5 inside MakeComposeLock after guard 4 before staging; globaldb_integration_test + tx_pruner_test green | closed |
| T-14-07 | Elevation of Privilege | SetColdUploadStateHookForTest (TEST-ONLY override) | medium | mitigate | Mirrors the SetEraseInterruptHookForTest discipline: process-global, PRODUCTION-MUST-NEVER-CALL Doxygen, inert when unset, cleared in fixture teardown. Evidence: cold_prune_gate_test green proves the unset path; probe position pinned at TxPruner step 5 (kInterruptAfterColdGate = 5), never GlobalDB erase-hook steps 2/3 | closed |
| T-14-08 | Tampering | journal-CF seeding helper (test infrastructure) | medium | mitigate | Seeds only while GlobalDB is closed (RocksDB dir lock enforced mechanically); asserts record counts before writing. Evidence: SeedVariants/{NoRecord,Accepted,GarbageStateByte,GarbageVersionByte} green — garbage encodings defer, the helper can never manufacture a Durable permit | closed |
| T-14-09 | Repudiation | Unreadable observability (D-03/MI-02) | medium | mitigate | Dedicated cold_unreadable_groups counter + WARN asserted at gate level; corruption can never be healthy-by-omission. Evidence: UnreadableBridge_MapsRealFault + Gate_UnreadableDefersLoudlyAndCycleCompletes green (WARN observed via counting sink: exactly 1 per group per cycle) | closed |
| T-14-10 | Tampering | admission widening across the composition | high | mitigate | Crossing leg (c): non-erasable x Durable -> no erase and no cold-counter motion — the gate provably cannot widen eligibility. Evidence: Composition_NonErasableTimesDurableNeverErases green; PruneEligibility.{hpp,cpp} byte-identical (git diff --exit-code, re-run at phase close) | closed |
| T-14-11 | Information Disclosure | live smoke credentials | low | mitigate | The smoke reads endpoint/credentials from the env-gated runbook pattern only (no secrets at rest in the test or CMake); Tier-1 lane never executes the live leg. Evidence: cold_prune_live_smoke_test labelled SKIP captured verbatim; LABELS "Tier3"; tier1_static_audit green | closed |
| T-14-SC | Tampering | package installs (npm/pip/cargo) | high | accept | Zero package-manager installs across all three plans (in-repo C++ only, zero new dependencies per the v1.2 ruling); unplanned install halts the run | closed (accepted) |

*Status: open · closed · open — below high threshold (non-blocking)*
*Only open threats at or above workflow.security_block_on (high) count toward threats_open*

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| AR-14-01 | T-14-SC | Zero package-install surface in all three plans; unplanned-install halt covers residual risk | Plans 14-01..14-03 (owner-approved) | 2026-11-17 |

*Accepted risks do not resurface in future audit runs.*

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-11-25 | 12 | 12 | 0 | gsd-secure-phase (L1 short-circuit: plan-authored register, asvs_level 1, threats_open 0; cross-checked against 14-VERIFICATION.md — 12/12 must-haves passed at SuperGenius 095c8c502, 2026-11-17, five-state matrix + TOCTOU red-first legs green) |

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-11-25
