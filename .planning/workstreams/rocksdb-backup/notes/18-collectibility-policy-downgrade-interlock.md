# Collectibility Policy & Downgrade Interlock Rulings (v1.2 Phase 18)

**Ruled:** 2026-11-19
**Context commits:** SuperGenius `84d87d462` (research anchor, Phase 17 close) → `2c94e481b` (executed Phase 18 HEAD: 18-01 `69fa79c29`→`01d0e85d1`, 18-02 `ed4478169`→`65441090e`, 18-03 `8ce2557a4`→`c167ee838`→`2c94e481b`) on `dev_coldstorage_additions`
**Requirements:** POLICY-01 (cold collectibility as recorded policy), POLICY-02 (downgrade E2E + interlock)
**Decisions ruled here:** D-01 through D-14 (18-CONTEXT)

This is the policy record the Phase 18 code cites at its ruling sites (the both-homes discipline, notes/16 D-12 precedent): the `ColdStorageManager` walk-gap exemption consult, the `GeniusNode` downgrade disarm gate, the `PruneEligibility` ack-key/fingerprint homes, and the tiered-light posture line all cite this document by path. It joins `notes/16-txpruner-gc-composition-rulings.md` and `notes/17-seal-growth-decision.md` in the rulings chain.

---

## (a) The two-halves policy — cold is permanent this milestone

**Cold objects are permanent in v1.2.** The frozen sgns-blockstore v1 contract forbids `Remove` (REQUIREMENTS out-of-scope; CORE-05), and nothing this milestone may delete a cold object: no TxPruner path, no GC path, no bucket-lifecycle or S3-expiry path (AF-2). The **permanent-once-written invariant** holds unconditionally — local eviction (`EvictLocalAndMarkDisposed`) removes only the LOCAL copy and its journal record; the remote object always survives; seals are never erased by any path (GATE-03 / governing invariant 3).

**Collectibility machinery is an sgns-blockstore v2 contract ask — never built here.** The sketch in §(g) is the recorded ask; no collection capability ships in v1.2.

**The rule itself:** *collectibility and the GC walk-gap exemption are two halves of one rule — they ship together or not at all* (governing invariant 4). The hazard that binds them is the **poisoned-GC triangle** (PITFALLS Interaction A): on any light+cold+retention node that prunes, the pruned CID becomes unreadable to the GC walk (evidence outranks bytes on the serve path — `FetchNodeFromColdStorage` refuses with `HISTORY_PRUNED_LOCALLY` even while cold bytes exist), the walk sees a gap, and every subsequent pass aborts — **GC liveness broken from the first prune cycle onward**. 18-RESEARCH Pitfall 1 verified this state was LIVE on the pre-phase line: no v2 fault injection required. Consequently: enabling collection without the exemption ships breaks GC liveness, and the exemption without a collection capability costs nothing but must exist first — so the exemption shipped NOW, as code, and no collection can ever land without it already existing and tested.

## (b) The GC walk-gap evidence exemption — as shipped (18-01)

At the `WalkReachable` gap site (`ColdStorageManager.cpp`, the `GetNodeWithoutRequest` failure arm), the walk consults **the ONE Phase 15 predicate** — `GraphsyncDAGSyncer::LookupPruneEvidence` through the `gc_dag_syncer_` handle the walk already holds (D-02: the SERVE-03/D-04 source-consistency ruling extended to the GC walk; never a GC-local `/prune/blk` read, never error-code matching, never age). **Only the `Pruned` verdict exempts**: the CID becomes an expected-absent **terminal leaf** — counted, never descended into (its history is gone by definition). `Malformed`, `NoEvidence`, and the cold-disabled `nullopt` keep today's `pass-aborted-walk-gap` WARN + abort exactly (fail toward under-eviction; unreadable evidence is never exemption).

**Counted-continue (D-04):** `pass_walk_exempted_` (per-pass, reset beside `pass_reclaimed_count_`) publishes to `gc_last_pass_exempted_` (status atomic, `GetStatus().gc_last_pass_exempted`), surfaced in the per-pass line `gc: pass complete - {} candidate(s), {} evicted, {} walk-exempted (retention {} ms, dry_run {})` — the new field sits before the parenthesized options so existing tail-greps survive. Never-healthy-by-omission (Phase 14 D-03 / Phase 16 D-10 precedent): a persistently growing exempted count on a steady graph is the operator's early warning that v2 collection is eating the walk.

**Red-first evidence trail:** the counter-test `cold_gc_walk_gap_exempt_test` (Tier-1) was born red against the unmodified walk — LEG-1 (the live poisoned triangle: evidence PRUNED + hot gone + cold bytes PRESENT in both tiers) and LEG-2 (the v2 fault-injected state: cold deleted from both tiers via the fake's conformance-only Delete + `EvictLocal`) failed with the exact signature `gc: pass-aborted-walk-gap - CID <d1> is head-reachable but missing from every tier` (ctest exit 8, commit `69fa79c29`), then turned green with the consult (commit `01d0e85d1`). The fail-closed controls (NoEvidence genuine gap; Malformed value at a sanctioned-builder key) stayed green throughout. This red-then-green trail is the evidence chain any v2 collection milestone gates on.

**Pinned semantics:** the exempted leaf itself stays walk-visited (pinned — its own local cold copy is NOT evictable); what retention evicts is the non-pruned data BELOW the exempted link, which the leaf orphans (proven in 18-03's t3: the below-link spender block evicts and then serves remote-backed).

## (c) The downgrade interlock — as shipped (18-02)

A detected **archive/full → light+pruning** downgrade can never silently arm the pruner.

- **Detection (D-07):** a persisted node-local role fingerprint at `PruneEligibility::PRUNE_ROLE_FINGERPRINT_KEY` = `/prune/role-fingerprint` (the `/prune/` standalone-key family — never swept by GC hot-cleanup or any TxPruner path): `RoleFingerprintRecord` (node_type, pruning_enabled, cold_storage_enabled, written_at_unix_ms), read-compared-**rewritten** through `GlobalDB::GetRaw`/`PutRaw` by `RoleFingerprint::CheckAndRewrite`. The predicate is (prior node_type ∈ {Full, Archive}) AND (now Light) AND pruning enabled — the A2 ruling: ANY `ReplicatesAllAccounts` prior role is a source, not just Archive. **The rewrite is arm-selective (post-review correction):** the FirstRun / NoDowngrade / DowngradeAcknowledged arms rewrite the current posture; the **DowngradeUnacknowledged arm PRESERVES the prior record** — rewriting it to the light posture would let a second unacknowledged boot read `NoDowngrade` and arm silently (a supervisor crash-loop is not consent), so the interlock holds across ANY number of restarts until the ack key is set. The read-error and parse-failure arms never write (overwriting what could not be read is laundering).
- **Consent (D-05):** the deliberate ack key `downgrade_acknowledged` (bool, per-key type-checked, absent keeps false) inside the sgns_config.json `"pruning"` object — one key, one home.
- **Fire behavior (D-06):** on `DowngradeUnacknowledged` the node **starts normally** — serving, cold chain, sync all live — and the pruner stays DISARMED behind one loud WARN naming the ack key and this document's checklist (§d). Fail-toward-under-erase: a misconfigured node degrades to "keeps everything", never to "stops working" or "erases unacknowledged". Never refuse-to-start.
- **Safe arms:** a birth-tiered light node (no prior record) is `FirstRun` and NEVER fires (the DB-heuristic false positive, killed); a same-posture restart is `NoDowngrade`; an unreadable/corrupt fingerprint resolves to `UnreadableDisarm` **without overwriting the record** — no laundering an unreadable prior role through one reboot; the disarm persists until operator repair.
- **Wiring:** the check/rewrite runs at the TOP of `GeniusNode::StartPruneTimerIfConfigured` — ABOVE the pruning-enabled early return (an archive-era node typically runs pruning-disabled; a write gated on pruning-enabled would leave every later downgrade blind) — and the disarm gate sits between the Light check and the `TxPruner::New` arm. The verdict is computed **once per process and the disarm latches until restart** (defense in depth on top of the preserved record: the wiring site is reached once per account generation, and the latch keeps the WARN one-shot). The gate's wiring — consult above the early-return, WARN placement, WARN literals, posture line — is pinned by the `ColdDowngradeWiringGate.InterlockGateWiringPinnedInGeniusNode` source-scan leg (the EraseSurfaceGateTest precedent).

## (d) Operator checklist — the canonical home (D-08)

Before setting the ack key on a node that has detected a downgrade (the WARN cites this section by path):

1. **Verify another archive replica exists** for the history this node will prune. A downgraded light node refuses its own pruned history (`HISTORY_PRUNED_LOCALLY`); another archive/full node must hold it. If none exists, do NOT acknowledge — revert the role change instead.
2. **Verify the remote tier healthy.** The archive-era Durable evidence is the prune gate's input (Phase 14: existing Durable records satisfy the gate with no re-drain — 18-03 t2). An unhealthy remote means the last-copy guarantees this policy relies on are not in force.
3. **Review the timeline implications** (§f): markers accumulate post-downgrade, refusal activates on pruned CIDs, and local cold copies of below-link data become retention-eligible.
4. **Set the ack:** `"downgrade_acknowledged": true` inside the `"pruning"` object of sgns_config.json, then **restart** to arm pruning. Removing the key re-arms the interlock for the next detected transition.

## (e) The tiered-node model

| Posture | Cold | Role | Prunes | Notes |
|---|---|---|---|---|
| **Archive** | ON | Archive | Never (GATE-01 role gate) | Replicates all accounts; the downgrade SOURCE posture |
| **Tiered-light** | ON | Light | Node-locally (with consent + interlock) | The §3.5 posture: cold chain serves, local pruning may erase node-locally; the startup INFO line `cold storage enabled on Light node - tiered-light posture: ...` cites this document |
| **Plain-light** | OFF | Light | Node-locally | The v1.1 baseline; no cold tier, no cold gate |

Downgrade transitions (interlock applies): Full/Archive → Light with pruning enabled. NOT downgrades: a birth-tiered light (FirstRun), a role change back toward replication, same-posture restarts.

## (f) The downgrade timeline t0→t3 — as E2E-proven (18-03)

Single-node in-process re-open topology (D-09: same DBs + cold config, only the role flips across `ShutdownNow`/rebuild; the 2-node real-pubsub topology was rejected — testing trap 5). Each stage cites its `cold_downgrade_e2e_test` leg (`TimelineT0ThroughT3`, Tier-1):

- **t0 archive era** — linked spend topology seeded through the real CRDT Put path; all-Durable (journal + remote objects); the archive-posture fingerprint written (`FirstRun`, record parses as Archive).
- **t1 light re-open** — the interlock fires (`DowngradeUnacknowledged`); zero markers while disarmed; the remote tier intact; the ack leg returns `DowngradeAcknowledged`.
- **t2 prune cycle under light rules** — with the drainer structurally held (faulted Put + unreachable admin: no drain/flush can advance anything), `TxPruner::RunCycle` erases archive-era groups (`erased > 0`) while the erased groups' journal records **stay Durable across the cycle** — SC3's no-re-drain proven the strong way; markers flip `NOT_FOUND`→`PRUNED` (produced by the real erase path); `GetNodeWithoutRequest` on the pruned CID refuses with `HISTORY_PRUNED_LOCALLY`; every remote object unchurned (structurally: no successful Put since t0).
- **t3 steady state** — retention 1ms + real GC: the pass COMPLETES through the exemption in-band (`gc_last_pass_exempted > 0`); the below-link spender block (orphaned by the exempted leaf) is retention-evicted through the real GC path (`IsColdDisposed`), then **serves remote-backed** from the persistent remote (the read rehydrates); refusal persists; seals untouched; every remote object remains.

**Cross-node letter (D-10 — recorded so verification does not re-litigate):** SC2's "history remains fetchable from other archive nodes" composes on landed semantics — Phase 15 SERVE-04 (the distinct local refusal + requester per-CID failover) and develop's SURV-02/19-07 (pruned-server refusal + clean failover to a serving peer). The t2 refusal observable IS the failover signal; no new cross-node test was built, by decision.

**Live confirmation (D-03/D-11):** `cold_downgrade_live_smoke_test` (Tier-3, dev-gated via `SGNS_BLOCKSTORE_TEST_MINIO_BIN`, loud labelled skip without it) runs the compact timeline on a real MinIO server through the production S3 client, including one post-prune GC pass surviving via the exemption (the LEG-1-shaped live state). The deterministic stand-in is the Tier-1 suite above.

## (g) The v2 contract-ask sketch — `Remove` (D-14, NOT BUILT)

- **What it must require:** collection is **evidence-driven, node-local, per-CID** — collect ONLY against node-local prune evidence (a `/prune/blk` row whose record decodes), never age, never watermark heuristics, never bucket-level lifecycle. The one-predicate discipline (D-02) applies: the same evidence source the serve path, the forced walk, and now the GC walk consult.
- **Why:** the two-halves rule (§a) and the poisoned-GC-triangle. Collection without the walk exemption breaks GC liveness from the first collected CID; the exemption without collection is inert but must pre-exist. **Precondition 1 (satisfied):** the exemption shipped and tested — `cold_gc_walk_gap_exempt_test` (Tier-1, red-first) exists at the time of this record; any v2 milestone extends, never re-litigates, it.
- **Precondition 2:** the **Durable-then-`DisposedDurable` lifecycle pointer** — the starvation interplay notes/16 §(a)/(d) records: v2 collection should preserve terminal journal evidence (`DisposedDurable`, REQUIREMENTS Future) instead of deleting the journal record, so TxPruner's gate reads a positive terminal state instead of consulting a second keyspace.
- **Cross-references (REQUIREMENTS Future entries):** "Cold collectibility machinery (per-CID evidence-driven S3 deletion) — blocked on sgns-blockstore v2 contract (CORE-05 forbids Remove in v1)"; "`DisposedDurable` journal terminal state (or remote-presence verification) as the v2 answer to the starvation interplay." A future milestone plans against those rows + this sketch without re-deriving requirements, hazards, or preconditions.

## (h) Options considered and rejected

| Option | Verdict | Why |
|---|---|---|
| **Design-record-only exemption** (document the abort as a future failure mode) | **Rejected** (D-01) | Documented-not-enforced: v2 collection could ship against a walk that was never proven to survive evidence. The strongest SC1 form is "no collection can ever land without the exemption already existing and tested". |
| **Tripwire-test-only exemption** (a failing test pinning the hazard, no production fix) | **Rejected** (D-01) | The triangle is LIVE today — a tripwire leaves production GC broken from the first prune cycle on any pruning light+cold node. |
| **WARN-only interlock** (advisory log on detected downgrade) | **Rejected** (D-05) | Only as strong as log-review discipline. The ack key + disarm gate make "operator-initiated, checklist-gated" mechanically enforced. |
| **DB-content downgrade heuristic** (markers + Durable records imply downgrade) | **Rejected** (D-07) | A birth-tiered light's first prune cycle matches the same signature — the false positive. The persisted fingerprint distinguishes cleanly and is hermetically testable. |
| **2-node real-pubsub downgrade E2E** | **Rejected** (D-09/D-10) | The repo's flakiest test class (testing trap 5: N-node portability landmines); cross-node semantics already proven on Phase 15's line. Compositional coverage recorded in §(f) instead. |
| **GlobalDB-injection consult seam** (expose the predicate to the GC pass via OpenColdStorageStack injection) | **Rejected** (18-01 planner ruling) | Unnecessary: `GraphsyncDAGSyncer::LookupPruneEvidence` is public and ungated on the post-17 line; routing through the handle the walk already holds is consistency-by-construction. |
| **Refuse-to-start on unacknowledged downgrade** | **Rejected** (D-06) | Violates fail-toward-under-erase: a misconfigured node must degrade to "keeps everything", never "stops working". |

## Evidence

- **18-01** (`cold_gc_walk_gap_exempt_test`, Tier-1): red commit `69fa79c29` — LEG-1/LEG-2 failing with `gc: pass-aborted-walk-gap` (ctest exit 8), controls green; green commit `01d0e85d1` — all legs green, exempted > 0, repeat-pass identical counts, zero-baseline leg; full Tier-1 lane green; source gates (no GC-local `/prune/` read, no hand-built keys).
- **18-02** (`cold_downgrade_e2e_test` verdict matrix, Tier-1): FP-FirstRun (birth-tiered-light never fires + posture recorded), FP-DowngradeFire, FP-AckArms, FP-FullFires (A2), FP-UnreadableDisarm (corrupt record preserved un-overwritten), FP-SamePosture, FP-UnackedPersists (the 18-REVIEW F-1 regression pin: an unacknowledged downgrade re-fires on the second check — the prior record is preserved, never rewritten), CFG-AckParse (per-key type-checked parse). GeniusNode wiring pinned by the `ColdDowngradeWiringGate.InterlockGateWiringPinnedInGeniusNode` source-scan leg (consult above the enabled early-return; both WARN literals between the Light check and the arm; the checklist-path citation; the tiered-light posture line).
- **18-03** (`cold_downgrade_e2e_test` `TimelineT0ThroughT3`, Tier-1; `cold_downgrade_live_smoke_test`, Tier-3): the t0→t3 assertions itemized in §(f); live leg loud-skips ungated with the labelled message naming its deterministic stand-in.
- **Compositional cross-node basis:** Phase 15 SERVE-04 (refusal + failover) and develop SURV-02/19-07 — cited, not re-proven (D-10).
- **Deviations as-landed** (doc/code truthfulness): the once-per-process verdict latch at the per-generation wiring site (18-02); the t3 GC thread drive + admin-unfault posture and the below-link eviction class (18-03); the ColdStorageStatus field home in ColdStorageStack.hpp and the compose-matrix LEG M8 fixed-point posture update (18-01). Each is recorded in the corresponding SUMMARY.

## Forward pointers

- **Phase 19 capstone** (fault-race matrix + three-platform CI): inherits the Tier-1 lane entries `cold_gc_walk_gap_exempt_test` (#112), `cold_downgrade_e2e_test` (#113), and the Tier-3 `cold_downgrade_live_smoke_test` — the label/lane discipline is part of this record's contract.
- **A future v2 collection milestone:** REQUIREMENTS Future rows (cold collectibility machinery; `DisposedDurable`) + §(g) here + the 18-01 red-first trail as the entry gate.
- **notes/16** (TxPruner × GC composition) and **notes/17** (seal growth): the chain this document joins; the operator checklist (§d) is the canonical procedural home the landed WARN texts cite.
