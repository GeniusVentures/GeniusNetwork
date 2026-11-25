---
phase: "16"
slug: "txpruner-gc-composition-hardening"
status: verified
# threats_open = count of OPEN threats at or above workflow.security_block_on severity (the blocking gate)
threats_open: 0
asvs_level: 1
created: "2026-11-24"
---

# Phase 16 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.

> Input state B (no prior SECURITY.md; created retroactively from PLAN registers + SUMMARY evidence + the 2026-11-24 refreshed verification).
> L1 short-circuit applied: threats_open 0 · register authored at plan time · asvs_level 1 (no auditor spawn required).

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| committed erase → LRU cache | post-commit invalidation crosses from the durable batch commit into the process-local cache; a missed invalidation serves locally-erased bytes | cache invalidation |
| test seam → production compose path | the observer static fires inside EraseEntry's compose window; an escaped hook mutates production | test hook state |
| GC-owned journal/marker keyspace → TxPruner admission decision | the disposed-marker read crosses module ownership; a hand-built key silently misclassifies stranded mass | disposed-marker rows |
| disposal commit → subsequent prune cycle | the starvation window — journal gone, remote serving, gate reading NoRecord | journal/remote state |
| concurrent pruners → shared keyspaces | two destructive systems write overlapping surfaces with no coordination | marker/binary/set keys |
| injected durability flip → two destructive readers | the state a destructive decision was predicated on changes between read and act | durability journal |
| race legs → CI trust | flaky real-thread legs erode the fail-closed lane | test results |

---

## Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation | Status |
|-----------|----------|-----------|----------|-------------|------------|--------|
| T-16-01 | Information Disclosure | stale LRU entry serving erased bytes after commit | high | mitigate | Post-commit DeleteCIDBlock immediately after the commit, both exits. Evidence: verifier 2026-11-24 held at HEAD (strictly between commit `globaldb.cpp:1739` and seal re-assert `:1763`, unconditional); W1/W2 legs + red-first capture; cold_compose_matrix_test re-run PASSED (37.14s) | closed |
| T-16-02 | Tampering | observe-and-continue seam altering production erase outcomes | medium | mitigate | void contract + TEST-ONLY Doxygen + nullptr-clear + fixture teardown; W3 proves aborted erases never reach the observer fire site | closed |
| T-16-03 | Denial of Service | lock-order inversion calling into the syncer under the compose lock | medium | mitigate | DeleteCIDBlock verified lock-free (graphsync_dagsyncer.cpp:1258-1265); no lock acquisition introduced at the call site; no deadlock across Tier-1 runs | closed |
| T-16-04 | Tampering | last-copy destruction under starvation misclassification (NoRecord arm) | high | mitigate | Disposed → stranded counter + defer, NEVER erase; consult error → freeze-safe false → defer. Evidence: verifier held the S3a chain at HEAD (IsColdDisposed → free bridge → ColdStorageManager::IsDisposed → library); `cold_disposed_stranded={}` split counter surfaces the strand | closed |
| T-16-05 | Information Disclosure | stranded prune mass invisible inside cold_deferred_groups | medium | mitigate | Dedicated counter + INFO surfacing (D-10/MI-02); lifecycle record consumed by phases 17/18 | closed |
| T-16-06 | Tampering | third marker builder / keyspace drift | medium | mitigate | Library-owned route only; PruneEligibility zero-diff gate; one-builder-per-namespace discipline | closed |
| T-16-07 | Tampering | crossfire — one pruner's staging eating another namespace's evidence | high | mitigate | M5/M6 exact-prefix enumeration: marker maps byte-identical across runs; touched-set diffs exactly the expected keys | closed |
| T-16-08 | Tampering | divergent interleavings undetected (orders never compared to each other) | high | mitigate | M1-M4/M8 fixed-point reference (twin snapshot) comparison, not per-order expectations | closed |
| T-16-09 | Tampering | contradictory durability beliefs destroying the last copy (Interaction C) | high | mitigate | R3 flips state at every straddle ordering asserting last-copy survival; D-02 lock serialization verified at af644481f, both homes documented | closed |
| T-16-10 | Denial of Service | flaky real-thread legs eroding the Tier-1 CI contract | medium | mitigate | WindowGate barriers, poll predicates, seeded jitter with env knobs, distinct fixture dirs, double Tier-1 runs before commit. Evidence: three-platform CI capstone green (phase 19, Tier-1 20/20) | closed |
| T-16-SC | Tampering | package installs (npm/pip/cargo) | high | accept | Zero package-manager installs across all three plans (zero new dependencies per the v1.2 ruling); unplanned install halts the run | closed (accepted) |

*Status: open · closed · open — below high threshold (non-blocking)*
*Only open threats at or above workflow.security_block_on (high) count toward threats_open*

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| AR-16-01 | T-16-SC | Zero package-install surface in all three plans; unplanned-install halt covers residual risk | Plans 16-01..16-03 (owner-approved) | 2026-11-18 |

*Accepted risks do not resurface in future audit runs.*

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-11-24 | 11 | 11 | 0 | gsd-secure-phase (L1 short-circuit: plan-authored register, asvs_level 1, threats_open 0; cross-checked against the refreshed 16-VERIFICATION.md — 3/3 must-haves at HEAD with fresh digest) |

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-11-24
