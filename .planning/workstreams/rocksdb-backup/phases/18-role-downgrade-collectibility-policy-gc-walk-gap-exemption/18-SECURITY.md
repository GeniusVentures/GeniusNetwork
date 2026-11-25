---
phase: "18"
slug: "role-downgrade-collectibility-policy-gc-walk-gap-exemption"
status: verified
# threats_open = count of OPEN threats at or above workflow.security_block_on severity (the blocking gate)
threats_open: 0
asvs_level: 1
created: "2026-11-25"
---

# Phase 18 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.

> Input state B (no prior SECURITY.md; created retroactively from PLAN registers + SUMMARY evidence + the phase's own VERIFICATION.md).
> L1 short-circuit applied: threats_open 0 · register authored at plan time · asvs_level 1 (no auditor spawn required).

---

## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| persisted /prune/blk evidence -> GC walk verdict | node-local records written by the erase path are now consumed by a liveness-critical walk; corrupt or hostile rows could steer eviction decisions |
| the one predicate (ColdReadService lookup) -> every classifying surface | serving, forced walk, and now the GC walk project from one source; a second surface would fork the truth |
| pass-exempted counter -> operator visibility | the INFO/status numbers are the early-warning surface for future v2 collection; miscounting hides drift |
| sgns_config.json -> pruning consent | operator-controlled config arms a state-destroying capability (pruning post-downgrade); a stray edit or tamper must not silently enable it |
| persisted fingerprint -> downgrade verdict | node-local persisted input parsed at startup; corrupt/missing rows must never resolve to the armed direction |
| config file + fingerprint -> WARN text -> operator action | the WARN is the operator-facing recovery instruction; a vague or wrong path turns the interlock into an outage generator |
| fixture-replayed archive era -> verdict/evidence consumers | the E2E seeds the archive era through real CRDT puts; any shortcut seeding (hand-built markers, direct journal writes) would falsify the SC3 evidence |
| persistent in-memory fake <-> real durable remote | the fake models the remote tier across re-opens; a modeling slip (fakes rebuilt, objects lost) would pass vacuously or fail spuriously |
| Tier-3 env gate <-> CI lane separation | a live leg leaking into Tier-1 would put MinIO dependencies on every CI runner |
| the record -> future v2 collection planning | a future milestone plans directly against this doc; an ambiguous or overpromising sketch becomes scope creep or a broken precondition |
| the record <-> landed code/tests | every claim must resolve to committed evidence; drift between doc and code turns the rulings chain into misinformation |

---

## Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation | Status |
|-----------|----------|-----------|----------|-------------|------------|--------|
| T-18-01 | Tampering | exemption opening on non-evidence (silent skip of real gaps -> under-counted reachability -> wrongful local eviction) | high | mitigate | Consult opens ONLY on the Pruned verdict of the one predicate; second-evidence-surface source gate. Evidence: verifier 2026-11-19 — ColdStorageManager.cpp:859-880 (LookupPruneEvidence, only Pruned continues, ++pass_walk_exempted_); CONTROL-NoEvidence/CONTROL-Malformed legs green; no raw /prune/ read in ColdStorageManager.cpp | closed |
| T-18-02 | Tampering | malformed /prune/blk row at the gap treated as exempted | medium | mitigate | Malformed arm keeps today's abort (fail closed, mirroring the predicate's own arms). Evidence: CONTROL-Malformed leg corrupts a value at a sanctioned key and asserts abort (cold_gc_walk_gap_exempt_test, red 69fa79c29 -> green 01d0e85d1) | closed |
| T-18-03 | Repudiation | walk-exempted counter drift (counting passes not CIDs) hiding v2 collection growth | low | mitigate | Per-CID increment + per-pass reset + repeat-pass identical-count leg + no-evidence zero baseline; counter surfaced in INFO (never-healthy-by-omission) | closed |
| T-18-04 | Denial of Service | exemption turning the walk into an unbounded skip that validates partial history | medium | mitigate | Exempted CIDs are terminal leaves (links never traversed — Pitfall 6); walk_exact still means every reachable non-exempted link was seen. Evidence: Tier-1 GC lanes prove unchanged walk semantics | closed |
| T-18-05 | Elevation | silent downgrade via config tamper (node_type + pruning flipped without consent) | high | mitigate | D-05/D-07 interlock: persisted fingerprint + ack key + disarm WARN — the phase's core V4.1 deny-by-default control. Evidence: FP-DowngradeFire / FP-AckArms / FP-FullFires green; GeniusNode.cpp:5210-5300 consult above the !pruning_config_.enabled early-return, both disarm WARNs between the Light check and the TxPruner::New arm, once-per-process latch, start-normally | closed |
| T-18-06 | Tampering | malformed fingerprint record arming the pruner (parse-failure -> arm-anyway) | high | mitigate | UnreadableDisarm arm resolves SAFE on every read/parse failure; corrupt record never overwritten (no laundering). Evidence: FP-UnreadableDisarm green; read-error arm returns UnreadableDisarm with NO write (PruneEligibility.cpp:741-752), parse-failure arm preserves the corrupt record (:753-765); 18-REVIEW F-1 fix preserves the prior record on the unack'd arm (:767-783) pinned by the FP-UnackedPersists regression leg (cold_downgrade_e2e_test.cpp:661-691) | closed |
| T-18-07 | Tampering | fingerprint swept/deleted by GC or TxPruner -> next boot reads FirstRun -> silent arm | medium | mitigate | /prune/ standalone-key family (no sweep path touches it — RunHotCleanup deletes exactly block binary keys + membership rows); keyspace documented at the key static. Evidence: source-verified; t1 verdict DowngradeUnacknowledged over the re-opened stack persists to t3 | closed |
| T-18-08 | Denial of Service | interlock degrading past its contract (blocks startup, breaks serving) | medium | mitigate | D-06 start-normally + disarm-only posture; the gate sits below everything the node already did. Evidence: Tier-1 lane proves non-downgrade boots are byte-identical; no refuse-to-start anywhere | closed |
| T-18-09 | Repudiation | operator consent ambiguity (ack set without checklist) | low | accept | The ack key is a standing explicit config consent whose WARN cites the checklist path; the policy record (18-04) documents the checklist as the canonical procedure — enforcement beyond config-consent is process, not code, this milestone | closed (accepted) |
| T-18-10 | Repudiation | SC3 proven the weak way (live drainer re-advancing states invisibly under the assertion) | medium | mitigate | Held-drainer posture mandatory (faulted Put + Unreachable admin — structurally no advancement). Evidence: t2 held-drainer posture (faulted from t0 onward, :1011-1013); journal-stays-Durable asserted post-cycle (:1086-1094) | closed |
| T-18-11 | Tampering | E2E seeding shortcuts (hand-built markers/journal rows) fabricating the downgrade evidence | medium | mitigate | Markers observed via LookupPrunedBlockEntry and produced only by the REAL EraseEntry path in t2; hand-built-key source gate; seeding via real CRDT Put. Evidence: TimelineT0ThroughT3 (cold_downgrade_e2e_test.cpp:939) seeds through the real CRDT Put path, all-Durable | closed |
| T-18-12 | Denial of Service | live leg leaking into the Tier-1 CI lane (MinIO dependency on every runner) | medium | mitigate | LABELS Tier3 + the tier1-leak source gate (ctest -L Tier1 -N must not list it) + the env-gate loud-skip verified ungated. Evidence: cold_downgrade_live_smoke_test loud-skip verified (18-USER-SETUP.md posture, non-blocking per D-11) | closed |
| T-18-13 | Tampering | static test seams (interrupt hooks, client overrides) leaking between cases and corrupting later verdicts | low | mitigate | TeardownStack verbatim with seam-clearing FIRST on every teardown; fakes re-injected before New and cleared after (Pitfall 7 ordering). Evidence: verdict matrix green across all FP-* legs in one fixture | closed |
| T-18-14 | Tampering | the record overpromising (presenting collection as shipped or the cross-node claim as newly proven) | medium | mitigate | Flagged must-NOTs + concrete-anchor gates (every capability claim cites a suite/leg; the v2 surface stays labeled a contract ask; D-10 compositional wording pinned). Evidence: notes/18-collectibility-policy-downgrade-interlock.md §(a)/(b)/(g) — sketch labeled NOT BUILT; no collection capability ships (no /prune/ key constructed, no GetRaw in the GC TU) | closed |
| T-18-15 | Repudiation | doc/code drift (record describing mechanisms that differ from what landed) | medium | mitigate | Task 1 reads the three SUMMARYs (including deviations) and cites legs by their landed names; anchor gates require the concrete identifiers (ack key, fingerprint key, error code, suite names) that only exist if the doc matches the code | closed |
| T-18-16 | Information Disclosure | operator checklist leaking environment specifics (paths, credentials) into the planning tree | low | accept | The checklist names config keys and verification steps only — no secrets, no host specifics; the planning tree is internal and the checklist is deliberately generic | closed (accepted) |
| T-18-SC | Tampering | package installs (npm/pip/cargo) | high | mitigate | No package-manager installs across all four plans (in-repo C++ + documentation only, zero new dependencies per the v1.2 ruling); any unplanned install halts the run | closed |

*Status: open · closed · open — below high threshold (non-blocking)*
*Only open threats at or above workflow.security_block_on (high) count toward threats_open*

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| AR-18-01 | T-18-09 | Operator consent beyond config-consent is process, not code, this milestone; the WARN cites the checklist path and the policy record documents it as the canonical procedure | Plan 18-02 (owner-approved) | 2026-11-19 |
| AR-18-02 | T-18-16 | Checklist deliberately generic — config keys and verification steps only, no secrets or host specifics; planning tree is internal | Plan 18-04 (owner-approved) | 2026-11-19 |

*Accepted risks do not resurface in future audit runs.*

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-11-25 | 17 | 17 | 0 | gsd-secure-phase (L1 short-circuit: plan-authored register, asvs_level 1, threats_open 0; cross-checked against 18-VERIFICATION.md — 26/26 must-have truths at SuperGenius d2f2a7dec, 2026-11-19, incl. the 18-REVIEW F-1 critical fix + FP-UnackedPersists regression leg) |

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-11-25
