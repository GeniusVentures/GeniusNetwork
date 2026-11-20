---
phase: 18-role-downgrade-collectibility-policy-gc-walk-gap-exemption
workstream: rocksdb-backup
verifier_method: goal-backward (each SC + each plan's must_haves checked against the codebase and committed evidence; no rebuilds — test results relied on as executed this session at SuperGenius d2f2a7dec on dev_coldstorage_additions)
status: passed
score: 26/26 must-have truths (12/12 prohibitions held; all artifacts present — 2 recorded additive deviations)
requirements_covered: [POLICY-01, POLICY-02]
human_verification:
  - "Dev-opt-in UAT (NON-BLOCKING, recorded posture): the Tier-3 cold_downgrade_live_smoke_test gated execution on a real MinIO server (SGNS_BLOCKSTORE_TEST_MINIO_BIN + one-time bucket) — 18-USER-SETUP.md, status Incomplete. The committed verification posture per D-11 is the automated loud-skip contract (verified green) + the Tier-1 deterministic stand-in timeline (verified green); the live run is opt-in confirmation, not a phase gate."
date: 2026-11-19
---

# Phase 18 Verification — Role Downgrade, Collectibility Policy & GC Walk-Gap Exemption

**Phase goal:** *Cold collectibility ships as the two-halves rule — permanent-cold-this-milestone policy and the GC walk-gap evidence exemption recorded together — and an archive→light downgrade is E2E-proven as the composed flow.*

**Verified at:** SuperGenius `d2f2a7dec` (HEAD, `dev_coldstorage_additions`); full Tier-1 lane 19/19 passed, exit 0 (this session — includes `tier1_static_audit`, `cold_storage_gc_test`, `cold_compose_matrix_test`, `cold_evidence_matrix_test`, `cold_prune_gate_test`, `cold_prune_toctou_test`, `cold_seal_growth_test`, and the two new suites `cold_gc_walk_gap_exempt_test`, `cold_downgrade_e2e_test`).

**Commit trail confirmed on the branch:** `69fa79c29` (red-first test) → `01d0e85d1` (green consult) → `ed4478169`/`65441090e` (interlock substrate + gate) → `8ce2557a4`/`c167ee838`/`2c94e481b` (t0–t2, t3, live smoke) → `d2f2a7dec` (18-REVIEW F-1..F-4 fix).

---

## Success Criteria

### SC1 — The two-halves policy recorded as ONE document (the exemption included) — **VERIFIED**

**Letter:** a recorded policy decision documents cold objects permanent this milestone, the permanent-once-written invariant, collectibility machinery as an sgns-blockstore v2 contract ask (frozen v1 forbids Remove), and — in the same record — the GC walk-gap evidence exemption (what may be absent = what may be collected; no collection can ever land without the exemption).

**Evidence:**
- The record exists at `notes/18-collectibility-policy-downgrade-interlock.md` (SC1's exact cited path): §(a) the two-halves policy (permanent-cold, permanent-once-written invariant, v2-not-built, AF-2 no bucket-lifecycle/S3-expiry), §(b) the exemption record as shipped, §(g) the v2 `Remove` contract-ask sketch with the satisfied-precondition citation ("no collection can ever land without the exemption already existing and tested" — §a closing rule).
- The exemption is not merely documented — it is CODE: the gap-site consult + counted-continue at `ColdStorageManager.cpp:859-880` (`gc_dag_syncer_->LookupPruneEvidence(current)`, only `Pruned` continues, `++pass_walk_exempted_; continue;`), proven by the red-first Tier-1 suite (`cold_gc_walk_gap_exempt_test`, red `69fa79c29` → green `01d0e85d1`).
- No collection capability ships: the GC TU constructs no `/prune/` key and has no `GetRaw` (source-verified — the only `/prune/` occurrence in `ColdStorageManager.cpp` is the ruling comment at :862); the sketch is labeled NOT BUILT; REQUIREMENTS.md Out-of-Scope/Future rows unchanged.
- `STATE.md:57` carries the date-stamped POLICY-01/02 one-liner citing the record by path.
- REQUIREMENTS.md: POLICY-01 `[x]` + traceability "Complete".

### SC2 — Archive→light downgrade E2E-proven; pruned history remains fetchable from other archive nodes — **VERIFIED** (cross-node letter compositional per D-10)

**Letter:** after downgrade the node prunes under light rules, and the history it pruned remains fetchable from other archive nodes.

**Evidence (downgraded half, Tier-1 `TimelineT0ThroughT3` in `cold_downgrade_e2e_test.cpp:939`):**
- t0 archive era seeded through the real CRDT Put path, all-Durable (journal + remote objects), archive-posture fingerprint written (FirstRun; record parses as Archive — asserted at :996-1010).
- t1 light re-open over the SAME DBs + cold config (`ShutdownNow`/rebuild, role flip only): verdict `DowngradeUnacknowledged` over the re-opened stack (:1024-1029), zero markers while disarmed (:1036-1039), remote tier intact (:1041).
- t2 prunes under light rules: `TxPruner::RunCycle` `stats.erased > 0` (:1084); remote S3 objects structurally unchurned (Put faulted from t0 onward — no re-upload is even possible — asserted via `ObjectKeys` equality at :1118-1120 and :1188-1189).

**Evidence (cross-node half):** per the D-10 compositional coverage ruling recorded in 18-CONTEXT/18-04 §(f) — the t2 refusal observable (`GetNodeWithoutRequest` fails `HISTORY_PRUNED_LOCALLY`, :1113-1115, persisting at t3 :1177) IS the failover signal; it composes on landed Phase 15 SERVE-04 (distinct pruned-vs-not-found refusal + requester per-CID failover) + develop SURV-02/19-07. **Not re-litigated per the verification brief.**

### SC3 — Archive-era Durable records satisfy the prune gate after downgrade; no re-drain, no migration — **VERIFIED (the strong way)**

**Evidence:** t2's held-drainer posture — S3 Put faulted `Unavailable` AND admin `Unreachable` from t0 onward (:1011-1013, held through t2) — means no drain pass or flush cycle can advance ANY journal record. Under that posture, archive-era Durable groups still erase (`erased > 0`) while the erased groups' journal records **stay Durable across the cycle** (:1086-1094, `GetColdUploadState == Durable` asserted post-cycle). Existing Durable evidence is the Phase 14 gate's input; the drainer is provably idle. No migration code exists anywhere in the diff.

### SC4 — Downgrade timeline observable end-to-end; config interlock prevents silent downgrade — **VERIFIED**

**Evidence:**
- **Markers accumulate post-downgrade:** `LookupPrunedBlockEntry` NOT_FOUND before the first cycle (t1, :1037-1039) → PRUNED after the real erase path runs (t2, :1097-1102).
- **Refusal activates:** `HISTORY_PRUNED_LOCALLY` at t2 and persisting at t3 (:1113, :1177).
- **Interlock mechanically enforced (operator-initiated, checklist-gated):**
  - `RoleFingerprint::CheckAndRewrite` (`PruneEligibility.cpp:694-800`): five verdict arms; **DowngradeUnacknowledged PRESERVES the prior record** (no `write_current_posture()` on that arm — the F-1 fix verified in code at :767-783); read-error arm returns `UnreadableDisarm` with NO write (F-2 fix, :741-752); parse-failure arm preserves the corrupt record (:753-765); A2 predicate = any `ReplicatesAllAccounts` prior → Light+pruning.
  - `GeniusNode.cpp:5210-5300`: consult ABOVE the `!pruning_config_.enabled` early-return; both disarm WARNs (naming `downgrade_acknowledged` + the notes/18 checklist path) BETWEEN the Light check and the `TxPruner::New` arm; once-per-process latch; start-normally (no refuse-to-start anywhere).
  - Tier-1 verdict matrix green: FP-FirstRun / FP-DowngradeFire / FP-AckArms / FP-FullFires / FP-UnreadableDisarm / FP-SamePosture / **FP-UnackedPersists** (the F-1 regression pin: second un-acked check fires `DowngradeUnacknowledged` again and the record still parses as Archive — `cold_downgrade_e2e_test.cpp:661-691`) + CFG-AckParse.
  - Wiring pinned mechanically by the source-scan leg `ColdDowngradeWiringGate.InterlockGateWiringPinnedInGeniusNode` (:711-758): consult-before-early-return, WARN ordering vs the arm, ack-key instruction, checklist-path citation, tiered-light posture line.
- **t3 steady state:** `gc_last_pass_exempted > 0` (the 18-01 exemption carrying the walk in-band, :1146-1149), below-link spender retention-evicted through the real GC path (`IsColdDisposed`, :1156) then served remote-backed (:1160-1169), seals untouched (:1180), every t0 remote object still present (:1189).

---

## Per-Plan Must-Have Spot-Checks

### 18-01 — GC Walk-Gap Exemption (red-first tracer): **7/7 truths**

| # | Truth | Verdict | Evidence |
|---|---|---|---|
| 1 | Exemption enforcement at the `WalkReachable` gap site; only `Pruned` continues; all other arms keep the abort | ✅ | `ColdStorageManager.cpp:869-892`: `Pruned` → `++pass_walk_exempted_; continue;`; Malformed/NoEvidence/nullopt fall through to the pre-existing `pass-aborted-walk-gap` WARN + `return {{},false}`. LEG-1/LEG-2 + both controls green in the 19/19 lane. |
| 2 | D-02 single predicate via `gc_dag_syncer_`; no GC-local `/prune/blk` read, no error-code matching | ✅ | Consult is exactly `gc_dag_syncer_->LookupPruneEvidence(current)`; source gate clean — no `/prune/` key construction, no `GetRaw` in the TU (grep-verified). |
| 3 | D-04 counted-continue observability (per-pass counter, status atomic, INFO field, never-healthy-by-omission) | ✅ | `pass_walk_exempted_` reset beside `pass_reclaimed_count_` (:951-954), relaxed-atomic publish (:982), INFO field before the parenthesized options (:983-986), `ColdStorageStack.hpp:123` `gc_last_pass_exempted{0}` field; zero-baseline leg `NoEvidenceBaselinePassReportsZeroExempted` green. |
| 4 | D-03 hermetic leg + red-first discipline | ✅ | Red commit `69fa79c29` on the branch (confirmed in git log); SUMMARY records ctest exit 8 with the exact `pass-aborted-walk-gap` signature; green `01d0e85d1`. |
| 5 | Idempotency edge: repeat pass = identical verdicts + stable count | ✅ | Repeat-pass leg inside LEG-1 (`cold_gc_walk_gap_exempt_test.cpp:628-636`): `pass2.size()==1`, exempted count IDENTICAL. |
| 6 | Concurrency edge (backstop): consult adds no writes/locks | ✅ | Pure read + counter increment under the existing `gc_pass_mutex_` critical section (single-writer, `WalkReachable`'s only caller is `EvaluatePass`); review's concurrency check found no issues; Phase 16 interleave suites green in-lane. |
| 7 | Zero regression on existing GC lanes | ✅ | Full Tier-1 lane 19/19 exit 0 this session; `cold_compose_matrix_test` LEG M8 posture-updated to the post-exemption disposal fixed point (recorded deviation, not a regression). |

Artifacts: all 4 present + 2 recorded additive deviations (`ColdStorageStack.hpp` status field; `cold_compose_matrix_test.cpp` LEG M8 posture). Prohibitions (no collection / no non-evidence signal / unreadable-never-exempts): all held in code and pinned by controls.

### 18-02 — Downgrade Interlock Mechanics: **7/7 truths**

| # | Truth | Verdict | Evidence |
|---|---|---|---|
| 1 | D-05/D-07 mechanics: ack key + persisted fingerprint + read-compare-rewrite via GetRaw/PutRaw | ✅ | `PruneEligibility.hpp:275` (`downgrade_acknowledged = false` default), `:440` (`PRUNE_ROLE_FINGERPRINT_KEY = "/prune/role-fingerprint"`), proto `RoleFingerprintRecord` (`SGTransaction.proto:99-109`), `CheckAndRewrite` via `GetRaw`/`PutRaw`. **Verified as-landed (post-F-1): the rewrite is arm-selective — FirstRun/NoDowngrade/DowngradeAcknowledged write; DowngradeUnacknowledged and both unreadable arms preserve. This is STRONGER than the plan's original wording and is what SC4's letter requires; the corrected contract is recorded in the header @note, notes/18 §(c), and the disposition.** |
| 2 | D-06 fire behavior: start normally, disarm behind a loud WARN; unreadable → safe arm | ✅ | `GeniusNode.cpp:5272-5297`: two distinct WARNs, both early-return (node keeps serving); no throw/refuse-to-start. |
| 3 | D-07 false-positive freedom: birth-light never fires; same-posture no-fire; Full fires like Archive | ✅ | FP-FirstRun (:765), FP-SamePosture (:868), FP-FullFires (:824) all green; A2 predicate `ReplicatesAllAccounts(prev) && Light-now && pruning` (`PruneEligibility.cpp:775-777`). |
| 4 | SC4 wiring half: consult above the enabled early-return; disarm between Light check and the arm | ✅ | Code order verified (:5224 consult → :5250 early-return → :5254 Light check → :5272/:5285 disarms → :5305 `TxPruner::New`); mechanically pinned by the F-3 source-scan leg. |
| 5 | A4 tiered-light posture INFO line citing the policy record | ✅ | `GeniusNode.cpp:713` `cold storage enabled on Light node - tiered-light posture: ...`; pinned by the source-scan leg. |
| 6 | Fingerprint idempotency/crash posture: same-posture second run NoDowngrade; corrupt record never overwritten; crash-between-read-and-write safe | ✅ | FP-SamePosture green; parse-failure arm returns `UnreadableDisarm` with NO write (:753-765) + `UnreadableDisarmPreservesCorruptRecord`; advisory-write posture (failed write = one warn, prior record re-detects). Post-F-1 the preserve discipline extends to the unack'd arm (`FP-UnackedPersists`) — the interlock now holds across ANY number of unacknowledged restarts. |
| 7 | Zero regression: non-downgrade boots arm exactly as pre-phase | ✅ | Tier-1 lane 19/19; FirstRun/NoDowngrade/ack arms rewrite exactly as before the fix. |

Prohibitions (no automatic/watermark downgrade; never arm on unacknowledged/unreadable + unswept keyspace; one-key-one-home ack surface): all held — the disarm arms never initiate or erase; `/prune/role-fingerprint` is a standalone key no GC/TxPruner path sweeps (review-verified: no prefix-sweep over `/prune/`); the ack key is a single bool inside the existing pruning object with per-key type-checked absent-keeps-default parse (CFG-AckParse green; F-6's silent ill-typed default accepted — fail-safe direction).

### 18-03 — Downgrade E2E t0→t3 + Tier-3 Live Smoke: **6/6 truths**

| # | Truth | Verdict | Evidence |
|---|---|---|---|
| 1 | SC2 downgraded half on the D-09 single-node re-open topology; remote unchurned structural; refusal activates; cross-node letter per D-10 | ✅ | See SC2 above — `erased>0`, Put faulted for the whole post-t0 timeline, `HISTORY_PRUNED_LOCALLY`, `ObjectKeys` equality across re-opens. |
| 2 | SC3 no-re-drain under the HELD drainer | ✅ | See SC3 above — faulted Put + Unreachable admin; journal stays Durable across the erasing cycle. |
| 3 | SC4 timeline observability: markers from zero, refusal, interlock fire at t1, ack arms | ✅ | See SC4 above — t1 `DowngradeUnacknowledged` + zero markers; ack leg `DowngradeAcknowledged`. |
| 4 | D-12 t3 steady state: exemption in-band, local cold eviction, remote-backed serving of non-pruned cold, seals untouched | ✅ | `gc_last_pass_exempted > 0` + `IsColdDisposed(spender)` + remote-backed `GetNodeWithoutRequest` + seals assert + all objects remain (timeline :1146-1189). Below-link eviction class recorded honestly (the exempted leaf itself stays walk-pinned — recorded deviation/clarification, matching notes/18 §(b) pinned-semantics). |
| 5 | D-03/D-11 live leg: Tier-3, env-gated, loud labelled skip, compact timeline when gated-in | ✅ | `CMakeLists.txt:605` LABELS "Tier3" (never Tier1 — `ctest -L Tier1 -N` leak check = 0 this session); `GTEST_SKIP() << "[SGNS_COLD_DOWNGRADE][LIVE-SMOKE] MinIO binary not provided..."` (`cold_downgrade_live_smoke_test.cpp:629`); builds + passes ungated via the LOUD skip (verified by direct binary run this session showing the labelled message). The gated live execution itself was NOT run (no MinIO binary in this environment) — the recorded dev-opt-in UAT posture per the plan's user_setup block and D-11 (see Human Verification). F-4 fix verified: the t2 verdict now asserts `DowngradeAcknowledged` exactly (:719). |
| 6 | Determinism posture: PollUntil bounded predicates, no wall-clock sleeps, distinct per-case dirs | ✅ | All waits are `PollUntil` on observables (journal Durable, exempted count, disposed, resolved); no sleeps in the timeline; per-case dirs. **Recorded deviation (accepted):** t3's GC pass is driven by the stack's own GC thread (retention 1ms + 50ms cadence + PollUntil) rather than direct `GcPassOnce` — the GlobalDB-owned manager is private; the compose-matrix fixture's own recorded posture; determinism preserved through the bounded predicates. |

Prohibitions (no N-node topology — held, single-node re-open only; SC3 never proven the weak way — held, the held-drainer posture is mandatory and used; no sleeps/no shared paths — held): all verified.

### 18-04 — The Policy Record: **6/6 truths**

| # | Truth | Verdict | Evidence |
|---|---|---|---|
| 1 | SC1 the record: one document, all content sections | ✅ | notes/18 carries §(a) two-halves policy, §(b) exemption record, §(c) interlock record (post-F-1 corrected wording verified: "the DowngradeUnacknowledged arm PRESERVES the prior record"), §(d) operator checklist, §(e) tiered-node model, §(f) t0→t3 timeline, §(g) v2 sketch, §(h) options table, Evidence, Forward pointers. |
| 2 | D-14 sketch depth: what/why/preconditions + REQUIREMENTS Future cross-refs | ✅ | §(g): evidence-driven/node-local/per-CID requirement, the two-halves + poisoned-triangle why, Precondition 1 (satisfied, citing the 18-01 suite) + Precondition 2 (DisposedDurable), both Future rows quoted. |
| 3 | D-08 canonical home: checklist in the record, WARNs cite it by path | ✅ | §(d) is the checklist; both GeniusNode WARN literals carry `notes/18-collectibility-policy-downgrade-interlock.md` (verified in source + pinned by the source-scan leg). One home, no copy in STATE.md (one-liner pointer only). |
| 4 | Evidence discipline: every claim resolves to committed evidence | ✅ | Evidence section cites the red signature + commits, all verdict-matrix legs by name, the timeline legs + observables, the compositional cross-node basis, and the as-landed deviations (doc/code truthfulness). |
| 5 | STATE.md one-liner | ✅ | `STATE.md:57` — date-stamped, cites the record by path, additive-only. |
| 6 | Options-considered-and-rejected present | ✅ | §(h): design-record-only, tripwire-only, WARN-only interlock, DB-heuristic, 2-node E2E, GlobalDB-injection seam, refuse-to-start — all with reasons. |

Prohibitions (no collection capability shipped/laundered; cross-node claim presented as compositional not newly-proven; checklist single home): all held.

---

## Flagged-Assumption Judgments (designated human-reviewed at verification)

1. **POLICY-02 edge probe (unclassified by the deterministic probe; decomposed by observable into the t0–t3 legs + interlock matrix).** **Judgment: adequately disposed — no human test required for the phase verdict.** Every locally-testable observable of POLICY-02's letter is pinned by a Tier-1 leg on a real GlobalDB: prunes-under-light-rules (t2 `erased>0`), markers + refusal (t2), no-re-drain (t2 held-drainer journal-stays-Durable), interlock fire/ack/persist (verdict matrix incl. FP-UnackedPersists), steady-state retention + remote-backed serving (t3). The single element no hermetic single-node test can observe — the literal fetch from ANOTHER archive node — is exactly the D-10 compositional ruling's subject (Phase 15 SERVE-04 + develop SURV-02/19-07, both tested on their own lines), which this verification is instructed not to re-litigate. The refusal observable that drives failover is directly asserted twice.
2. **A2 Full-fires ruling (Full→Light+pruning fires identically to Archive).** **Judgment: adequately disposed.** The planner-confirmed ruling is mechanically pinned by `FP-FullFires` (green in-lane); the predicate line in `PruneEligibility.cpp:775-777` is its exact implementation; no user override occurred at review.

---

## Review Disposition Verification (18-REVIEW.md → 18-REVIEW-DISPOSITION.md)

- **F-1 (CRITICAL) — fixed and verified in code + regression pin.** `PruneEligibility.cpp:767-783`: the DowngradeUnacknowledged arm returns WITHOUT `write_current_posture()` (preserve posture, mirroring the corrupt arm); `UnacknowledgedDowngradePersistsAcrossRestarts` pins the second un-acked boot re-firing with the record still parsing as Archive; the 18-03 t1 re-seed workaround removed; live-smoke t2 strengthened.
- **F-2 (MAJOR) — fixed and verified.** The read-error arm (:741-752) returns `UnreadableDisarm` with no write; the in-code comment states the no-laundering rationale.
- **F-3 (MAJOR) — fixed and verified.** The `ColdDowngradeWiringGate.InterlockGateWiringPinnedInGeniusNode` source-scan leg exists (`cold_downgrade_e2e_test.cpp:711-758`, `SUPERGNUS_DOWNGRADE_GATE_SRC` compile definition wired in `CMakeLists.txt:535`) and pins ordering + literals; deleting the interlock block now fails the lane.
- **F-4 (MINOR) — fixed and verified.** Live-smoke t2 asserts `DowngradeAcknowledged` exactly (`cold_downgrade_live_smoke_test.cpp:719`).
- **F-5/F-6 (ADVISORY) — accepted with rationale; consistent with the fail-toward-under-erase doctrine** (every garbage-value sub-case resolves to the safe direction; ill-typed ack key defaults to consent-absent). No action required for the phase.

All four actionable fixes are in final commit `d2f2a7dec` with the full Tier-1 lane 19/19 re-verified (per the disposition + this session's facts).

---

## Human Verification

**One non-blocking dev-opt-in item** (does not gate the phase verdict):

- **Tier-3 `cold_downgrade_live_smoke_test` gated execution** — requires `SGNS_BLOCKSTORE_TEST_MINIO_BIN` (community build) + the one-time bucket creation per `18-USER-SETUP.md` (status: Incomplete). **Ruling per D-11 posture honesty:** the plan's committed verification posture is the automated loud-skip contract (verified green — labelled message shown on direct binary run; lane-exclusion verified — `ctest -L Tier1 -N` does not list it) plus the Tier-1 deterministic stand-in timeline (green). The gated live run is opt-in live-wire confirmation of the same observables, in the established v1.1 TEST-03 dev-gate family, and its absence is the recorded posture — never silence. It belongs on the deferred-signals list (carried with TEST-03), not on this phase's critical path.

Nothing else requires human testing: every SC and must-have truth is pinned by deterministic Tier-1 evidence or direct source verification.

---

## Overall Verdict

**PASSED.**

- **Goal achieved, not just tasks completed:** the two-halves rule is real — the permanent-cold policy and the GC walk-gap exemption are recorded in ONE rulings document (notes/18), the exemption exists as tested production code with a red-first trail, no collection capability ships, and the archive→light downgrade is E2E-proven as a composed flow (Phase 14 gate + Phase 15 predicate/refusal + Phase 16 GC + the exemption + the interlock exercised as one timeline).
- **Score:** 26/26 must-have truths verified (7+7+6+6); 12/12 prohibitions held; all artifacts present (2 additive deviations recorded, both mechanical consequences of the designed behavior change); all executor deviations recorded truthfully and none weaken a must-have.
- **Requirements:** POLICY-01 and POLICY-02 complete (REQUIREMENTS.md checkboxes + traceability rows; STATE.md one-liner). Both requirement IDs accounted for.
- **Quality gate:** the phase's code review (CHANGES REQUESTED) is fully dispositioned — F-1..F-4 fixed and re-verified at `d2f2a7dec` (Tier-1 19/19), F-5/F-6 accepted with sound rationale. The CRITICAL finding's fix is regression-pinned.
- **Deferred:** the MinIO live-leg execution rides the existing dev-opt-in UAT/TEST-03 signal — recorded, loud, and non-blocking.

Phase 18 is verified complete; ready for STATE/ROADMAP bookkeeping and the Phase 19 capstone.
