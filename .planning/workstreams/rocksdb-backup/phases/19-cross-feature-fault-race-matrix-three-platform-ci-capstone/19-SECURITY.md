---
phase: "19"
slug: "cross-feature-fault-race-matrix-three-platform-ci-capstone"
status: verified
# threats_open = count of OPEN threats at or above workflow.security_block_on severity (the blocking gate)
threats_open: 0
asvs_level: 1
created: "2026-11-25"
---

# Phase 19 - Security

> Per-phase security contract: threat register, accepted risks, and audit trail.

> Input state B (no prior SECURITY.md; created retroactively from the five PLAN
> registers + SUMMARY evidence + the 2026-11-25 retroactive verification).
> L1 short-circuit applied: threats_open 0 -- register authored at plan time --
> asvs_level 1 (no auditor spawn required).

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| production code -> test seam | the serve interrupt hook is callable surface on GraphsyncDAGSyncer; production must never invoke it | step hook fn |
| test fixture -> shared static hook | a static hook armed by one case must not leak into the next case or production behavior | hook pointer |
| real threads -> fixture state | barrier legs race threads through shared fixture state; a parked hook under a lock hangs the lane | thread-visible state |
| seeded journal state -> gate decisions | the Phase 14 injection kit writes fixture-scoped journal CFs; seeded states must not leak across cases | journal rows |
| seeded evidence -> exemption decision | sanctioned writer output must be the only path to an exemption verdict | /prune/blk rows |
| budget accounting -> classification | X9 asserts the refusal-vs-not-found vocabulary boundary; misclassification is the hazard | counters |
| real gossip wire -> node states | X11 crosses real pubsub between two fixture nodes; wire flakes must surface as diagnostics, never silent skips | pubsub messages |
| teeth injections -> audited state | X10's byte-flip/counter injections must not corrupt other cases' fixture states | flipped objects |
| promotion contract -> lane honesty | an X11 flake must not be quietly excluded from the lane to go green | lane selection |
| workflow dispatch inputs -> runner shell | dispatch toggles and matrix contexts flow into run: blocks | env/matrix context |
| CI secrets -> logs | SGNS_BLOCKSTORE_S3_ADMIN_PASSWORD and tokens are near the lane steps' env | secrets |
| recorded evidence -> actual runs | the notes doc's green claims must trace to real run URLs | run links |

---

## Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation | Status |
|-----------|----------|-----------|----------|-------------|------------|--------|
| T-19-01 | Tampering | serve interrupt seam (graphsync_dagsyncer.hpp/.cpp) | high | mitigate | Production-null static hook (nullptr default, "no production caller" doc contract), fixture-destructor hook clearing; tier1_static_audit polices gated linking. Evidence: verifier 2026-11-25: seam at graphsync_dagsyncer.hpp:306-340, dispatcher at graphsync_dagsyncer.cpp:184, production-null note at hpp:443; audit test registered test/CMakeLists.txt:20-23 | closed |
| T-19-02 | Denial of Service | seam call sites + barrier legs | medium | mitigate | Hooks fire outside locks the publish path takes; WindowGate leak-proof destructors (idempotent Release); PollUntil bounded predicates. Evidence: verifier re-counted sleep_for = 1 (the re-declared PollUntil body only) in the 4,300+ line suite | closed |
| T-19-03 | Repudiation | fault arms under SGNS_CROSS_RACE_RED_ARMS_ENABLE | medium | mitigate | Knob never set in CI lanes; red signatures recorded per plan (2 -> 5/5 -> 9/9 carriers; X10 teeth ungated); VIOLATION gate in every verify block. Evidence: verifier grep: zero knob occurrences in both workflow files; red-arm carriers documented in 19-01..19-04 SUMMARYs | closed |
| T-19-04 | Tampering | journal-injection kit (direct CF seeding) | medium | mitigate | Seeding only into per-case fresh fixture dirs; sanctioned Phase 14 kit only, no new journal-write surface. Evidence: 19-02-SUMMARY zero-src-diff record; fresh-dir-per-case discipline in the suite header | closed |
| T-19-05 | Denial of Service | real-thread barrier legs (prune vs walk vs serve) | medium | mitigate | WindowGate idempotent Release, PollUntil bounded predicates, instrumented deadlines with status-dump-on-exhaustion, hooks cleared in fixture destructors. Evidence: D1-D8 dispatch trail: every wedge was diagnosed via status dumps and fixed forward (4f7281b1f, ebd8c80b8, 6e8b1610c), never a deadline bump | closed |
| T-19-06 | Tampering | X7 fault arm leaving a wrongly-exempted state visible to later cases | medium | mitigate | Fault arm strictly env-scoped + fresh fixture dir per case; fail-closed controls re-run INSIDE the case after the fault arm. Evidence: 19-03-SUMMARY run9/run10: controls green-and-stay-green, 9/9 carriers RED under the knob | closed |
| T-19-07 | Repudiation | jitter legs failing with irreproducible interleavings | low | mitigate | Every nondeterministic leg prints knob values + effective seed in its first log line; seeds uint64 via EnvOr; failure messages dump status structs. Evidence: suite header reproducibility contract (lines 75-84); knob print at cold_cross_feature_fault_race_test.cpp:799-800 | closed |
| T-19-08 | Denial of Service | X11 full-wire leg wedging on real-pubsub timing and burning the Tier-1 lane | high | mitigate | Generous instrumented deadlines + status-dump-on-failure; promotion contract (re-ruled one-green 2026-11-20, met at D4) with env-gated demotion path requiring a recorded ruling, never silent, never quarantined. Evidence: verifier: X11 green on all three platforms (D4; zero X11 failures D5-D8); no demotion triggered | closed |
| T-19-09 | Tampering | X10 teeth legs corrupting shared fixture state | low | mitigate | Teeth legs run last on dedicated fixture dirs (SuiteEnd ordering); audit walk precedes them. Evidence: 19-04-SUMMARY X10 ordering ruling | closed |
| T-19-10 | Information Disclosure | CI env secrets near the new lane steps | high | mitigate | New steps add ZERO secret env (ctest only, static expressions); SGNS_BLOCKSTORE_S3_ADMIN_PASSWORD stays presence-checked-never-echoed; no new secrets block. Evidence: verifier read of build-release-tags.yml:804-821/:949-959: only SGNS_TEST_P99_BOUND_MS (OSX) and static ctest text | closed |
| T-19-11 | Elevation | runner-side command injection via untrusted strings in run: blocks | high | mitigate | New steps use only static text + env/matrix context expressions, no inputs.* string flows into a run: block; COLD_STORAGE_ARGS env-context-only rule preserved. Evidence: verifier read of both new steps: ctest invocation is fully static | closed |
| T-19-12 | Repudiation | evidence links in notes/19-* drifting from actual runs | medium | mitigate | Links recorded verbatim from user-provided run URLs at the blocking checkpoint; parameters captured alongside; checklist cross-references the same run IDs: two homes, one fact. Evidence: verifier counted 5 run links in the notes doc, mirrored in 19-FRESH-CLONE-CHECKLIST.md (Windows/Linux D3 45257655488, OSX D7 45489840538, confirming D8 45504484532 at final HEAD) | closed |
| T-19-SC | Tampering | package installs (npm/pip/cargo) | high | mitigate | Zero package installs across all five plans and all 18 phase-19 commits (workstream zero-new-dependencies rule); the commit file inventory shows src/test/CI/docs files only, no manifest, lockfile, or package-manager surface touched | closed |

*Status: open / closed / open - below high threshold (non-blocking)*
*Only open threats at or above workflow.security_block_on (high) count toward threats_open*

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| (none -- every register entry carries disposition mitigate; T-19-SC is mitigated by the zero-install rule and re-verified against the commit inventory) | | | | |

*Accepted risks do not resurface in future audit runs.*

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-11-25 | 13 | 13 | 0 | gsd-secure-phase (L1 short-circuit: plan-authored register, asvs_level 1, threats_open 0; cross-checked against the retroactive 19-VERIFICATION.md) |

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log (none required -- no accept-disposition entries)
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-11-25
