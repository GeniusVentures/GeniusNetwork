---
phase: "15"
slug: "evidence-aware-cold-serving-forced-walk-recovery"
status: verified
# threats_open = count of OPEN threats at or above workflow.security_block_on severity (the blocking gate)
threats_open: 0
asvs_level: 1
created: "2026-11-24"
---

# Phase 15 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.

> Input state B (no prior SECURITY.md; created retroactively from PLAN registers + SUMMARY evidence + the 2026-11-24 refreshed verification).
> L1 short-circuit applied: threats_open 0 · register authored at plan time · asvs_level 1 (no auditor spawn required).

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| raw-store evidence → serve decision | the /prune/blk row read crosses from node-local storage into a serve/refuse decision on the read path — the boundary the resurrection gap lived at | PrunedBlockRecord rows (integrity-critical) |
| erase compose → marker evidence | markers staged in the same WriteBatch as the erase; a partial staging would create unprovable prune state | WriteBatch contents |
| re-warm worker → hot store | an asynchronous write path that can resurrect erased bytes if ungated | cached block bytes |
| evidence consult → walk routing | the tri-state answer crosses into traversal decisions — a misroute resurrects erased history or silently validates partial history | PruneEvidenceClass tri-state |
| bounded peer recovery → walk verdict | peer-failover exhaustion crosses into the abort decision — unbounded loop is a liveness hazard, silent one an integrity hazard | failover budget counters |
| test evidence → phase seal | the matrix/counter-test legs are the phase's verification surface — a dropped cell or guessed constant seals green over an untested path | test results |

---

## Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation | Status |
|-----------|----------|-----------|----------|-------------|------------|--------|
| T-15-01 | Tampering | evidence consult coverage (FetchNodeFromColdStorage, GetNodeWithoutRequest, RewarmWorkerLoop) | high | mitigate | ONE predicate fanned to all three surfaces; consult-first placement. Evidence: verifier 2026-11-24 re-ran X1/X2 fault legs live (2/2 PASSED) + the CR-01 fix-forward re-consults (:940 pre-Get, :974 pre-Rehydrate) verified at HEAD | closed |
| T-15-02 | Tampering | malformed /prune/blk classification | high | mitigate | Fail-closed Malformed → PRUNE_EVIDENCE_CORRUPT. Evidence: all three consult sites at HEAD (graphsync_dagsyncer.cpp:913/946/980); verifier confirmed "fail-closed malformed on both decoders" — also closes review finding WR-01 | closed |
| T-15-03 | Tampering | erase/marker atomicity (D-01) | high | mitigate | Both markers stage in the one compose-locked WriteBatch beside the erase. Evidence: LEG S3 + 15-03 interrupt-seam all-or-nothing legs; verifier held at HEAD through the phase-16 widened EraseEntry | closed |
| T-15-04 | Denial of Service | per-read evidence point lookup | low | accept | One O(1) RocksDB point read per cold-chain entry, no scans; consult-first skips cold I/O for pruned CIDs | closed (accepted) |
| T-15-05 | Tampering | walk-gap accounting | high | mitigate | Dedicated walk_gaps counter + FORCED_WALK_GAP error + frontier-clearing abort; W3 asserts all three counters zero. Evidence: verifier held at HEAD; phase-18 walk-gap exemption built on this machinery | closed |
| T-15-06 | Denial of Service | per-CID peer fan-out in recovery | medium | mitigate | kForcedWalkPeerFailoverPerCid count bound over the wall-clock + suppression layers. Evidence: D-12 verdict validated (8, in-band with noted limitation); X11 wire leg bounded-retry proven | closed |
| T-15-07 | Tampering | conflation regression (gap misreported as pruned skip) | high | mitigate | Matrix consults evidence FIRST; only Pruned/nullopt classes reach the skip; W2/W3 fix both masquerade directions behaviorally | closed |
| T-15-08 | Tampering | test integrity (guessed constants, dropped cells) | medium | mitigate | A5 discipline + parameterized enumeration with leg-count expectations. Evidence: cold_evidence_matrix_test 32/32 PASSED today (15.4s) | closed |
| T-15-09 | Denial of Service | flaky failover legs (gossip cache races) | medium | mitigate | Two-part proof (deterministic ordered-AddRoute half + DeleteCIDBlock between phases). Evidence: X11 full-wire leg green on CI (three platforms) | closed |
| T-15-10 | Repudiation | erase atomicity evidence | medium | mitigate | Interrupt-step legs prove all-or-nothing across BOTH markers from three intra-batch observation points | closed |
| T-15-SC | Tampering | package installs (npm/pip/cargo) | high | accept | Zero package-manager installs across all three plans (in-repo/test-only C++, zero new dependencies per the v1.2 ruling); unplanned install halts the run | closed (accepted) |

*Status: open · closed · open — below high threshold (non-blocking)*
*Only open threats at or above workflow.security_block_on (high) count toward threats_open*

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| AR-15-01 | T-15-04 | O(1) point-read cost per cold-chain entry is negligible; consult-first ordering saves the cold I/O for pruned CIDs | Plan 15-01 (owner-approved) | 2026-11-17 |
| AR-15-02 | T-15-SC | Zero package-install surface in all three plans; unplanned-install halt covers residual risk | Plans 15-01..15-03 (owner-approved) | 2026-11-17 |

*Accepted risks do not resurface in future audit runs.*

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-11-24 | 11 | 11 | 0 | gsd-secure-phase (L1 short-circuit: plan-authored register, asvs_level 1, threats_open 0; cross-checked against the refreshed 15-VERIFICATION.md and review disposition — CR-01 fixed forward in 19-01, WR-01 verified closed at HEAD) |

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-11-24
