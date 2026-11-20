---
phase: 18 — Role Downgrade, Collectibility Policy & GC Walk-Gap Exemption
workstream: rocksdb-backup
reviewed_range: SuperGenius 84d87d462..2c94e481b (branch dev_coldstorage_additions, 7 commits)
date: 2026-11-19
critical: 1
major: 2
minor: 1
advisory: 2
total: 6
verdict: CHANGES REQUESTED
---

# Phase 18 Source Review

Scope: the GC walk-gap evidence exemption (`ColdStorageManager`), the downgrade
interlock substrate (`PruneEligibility` ack key + `RoleFingerprint`), the
`GeniusNode` gate wiring, the `RoleFingerprintRecord` proto, and the four test
surfaces (three new suites + the compose-matrix LEG M8 posture update).

## Invariant verification (requested checks)

- **(a) Exemption opens ONLY on the Pruned verdict of the one predicate** —
  VERIFIED. `ColdStorageManager.cpp:869-871` consults
  `gc_dag_syncer_->LookupPruneEvidence(current)` (the Phase 15 predicate via
  the handle the walk already holds); only `Pruned` continues;
  `Malformed`/`NoEvidence`/cold-disabled `nullopt` all fall through to the
  pre-existing abort. No age check, no error-code matching. The GC TU contains
  no `/prune/` key construction and no `GetRaw` (single evidence surface
  holds).
- **(b) Exempted CIDs are terminal leaves** — VERIFIED. The `continue` at
  `ColdStorageManager.cpp:876-877` skips link descent entirely; the CID was
  inserted into `visited` before the fetch, so the leaf itself stays pinned
  (not evictable), matching the §(b) pinned-semantics ruling.
- **(c) Fail-toward-under-erase** — VERIFIED on the walk side (abort arms
  preserved; controls `ControlNoEvidenceGapStillAborts` /
  `ControlMalformedEvidenceStillAborts` pin them). On the interlock side the
  disarm arms are fail-closed **except** for two record-laundering paths —
  findings F-1 and F-2 below, where "fail-toward-under-erase" is violated one
  boot later rather than immediately.
- **(d) Corrupt fingerprint record never overwritten** — VERIFIED for the
  parse-failure arm (`PruneEligibility.cpp:752-763` returns `UnreadableDisarm`
  with no write; `UnreadableDisarmPreservesCorruptRecord` proves the bytes
  survive). F-2 shows the *read-error* arm does not share this discipline.
- **(e) WARN path never blocks startup** — VERIFIED. Both disarm gates are
  WARN + early-return inside `StartPruneTimerIfConfigured`; the node keeps
  serving/syncing; no throw, no refuse-to-start.
- **(f) No hand-built `/prune/*` keys in tests** — VERIFIED. Evidence keys
  come from `BuildPruneBlockMarkerKey`, the fingerprint key from the
  `PRUNE_ROLE_FINGERPRINT_KEY` static, marker reads via
  `LookupPrunedBlockEntry`. The hot-binary removal (`cid.toBytes()`) and the
  S3 `DeriveTestKey` replica are not `/prune/` keys.

## Concurrency / edge-case checks (no findings)

- `pass_walk_exempted_` is single-writer under `gc_pass_mutex_`:
  `WalkReachable` has exactly one caller (`EvaluatePass`, line 1046), which
  runs only inside `GcPassOnce`'s `gc_pass_mutex_` critical section; the reset
  (line 951-954) and the relaxed-atomic publish to `gc_last_pass_exempted_`
  (line 982) sit in the same section. Sibling-posture consistent with
  `gc_last_pass_reclaimed_*`.
- The `role_fingerprint_*` latch booleans in `GeniusNode` are plain bools, but
  every reachable caller path (`StateTransition` at line 1278) holds
  `lifecycle_mutex_`; consistent with the file's existing member discipline.
- `GetRaw`/`PutRaw` are committed-state point operations on the node-local
  RocksDB face — not CRDT-replicated, not broadcast (Pitfall 4 holds); the
  `/prune/role-fingerprint` key is not swept by any GC/TxPruner path
  (verified: no prefix-sweep over `/prune/` exists).
- Unencodable CID at the evidence lambda yields an empty `cid_string` →
  prefix-only key miss → `NoEvidence` → abort (fail-closed); the abort WARN's
  `<unencodable CID>` arm is pre-existing.
- `LoadSgnsConfig` (resolves `node_type_`, line 340) runs before
  `LoadCrdtConfig` (line 386), so the tiered-light posture INFO sees the real
  role; `tx_globaldb_` is assigned (line 2442) before `StateTransition` can
  reach the gate.
- `ColdStorageStatus{}` value-init (ColdStorageStack.cpp:330) zeroes the new
  field; no aggregate initializers of the struct exist; no positional
  dependencies broke.

---

## Findings

### F-1 — CRITICAL — Interlock is defeatable by one unacknowledged restart: the record rewrite on the `DowngradeUnacknowledged` arm launders the downgrade across a reboot

**File:** `SuperGenius/src/transaction/PruneEligibility.cpp:767-782`
(interacting with `SuperGenius/src/account/GeniusNode.cpp:5224-5300`)

**Description:** `CheckAndRewrite` calls `write_current_posture()`
(line 772) *before* returning `DowngradeUnacknowledged` (line 774-777). The
rewrite records the **current** posture — `(Light, pruning_enabled=true)` —
over the archive-era prior. Consequence across a plain restart with the
config **unchanged and still un-acked**:

- Boot 1 (the transition): verdict `DowngradeUnacknowledged` → gate disarms,
  loud WARN, record rewritten to `(Light, true)`.
- Boot 2 (no ack, no operator action — e.g. a supervisor/crash-loop/k8s
  restart): prior record parses as `Light` → `ReplicatesAllAccounts(Light)` is
  false → `downgrade=false` → `NoDowngrade` → the disarm flags never set →
  `TxPruner::New` arms and the prune timer starts. No WARN is emitted on this
  boot.

The interlock's enforcement window is therefore exactly **one boot**. This
contradicts, in the phase's own terms:

1. The policy record's headline — §(c): *"a detected archive/full →
   light+pruning downgrade can never silently arm the pruner"* — a restart
   arms it with zero operator action, and silently relative to the interlock.
2. The WARN's own operator contract — *"Set `downgrade_acknowledged`: true …
   and restart to arm pruning"* — mechanically, restart **alone** arms; the
   ack key's only real effect is on the detecting boot (immediate
   `DowngradeAcknowledged` vs. one disarmed boot).
3. The fail-toward-under-erase doctrine: the second boot erases without
   consent that was ever given.

The E2E test itself demonstrates awareness of the rewrite
(`cold_downgrade_e2e_test.cpp:942-944`: *"the unack check above just rewrote
[it] to the light posture"* — the ack leg re-seeds the archive record to get
past it) without drawing the arming consequence, and **no test covers the
second-boot-without-ack path** — the gap is unpinned. Note the summary of
18-02 records the within-process latch for exactly this laundering hazard
(*"a later generation re-checking … would read NoDowngrade and ARM"*) — the
same reasoning applies one level up, across the restart the latch defers to.

Mitigating context (why CRITICAL rather than "stop ship"): erasure remains
node-local, evidence-gated, and the remote cold tier is permanent this
milestone, so the blast radius is bounded — but the consent control this
phase exists to build is bypassable by a routine restart.

**Suggested fix:** skip `write_current_posture()` on the
`DowngradeUnacknowledged` arm — preserve the prior (archive/full) record
exactly as the corrupt-record arm does. Every un-acked boot then re-detects
and re-WARNs once per process (the "loud, not cadenced" D-06 posture, per
boot); setting the ack and restarting yields `DowngradeAcknowledged` → arm +
rewrite, preserving the documented fast path for a planned, checklist-complete
migration. `FirstRun`/`NoDowngrade`/`DowngradeAcknowledged` arms keep writing
(posture tracking for future transitions must continue). Add a verdict-matrix
leg pinning "second un-acked boot still disarms" and (if the fix lands) "ack +
restart arms". If a one-boot consent window is actually the intended ruling,
then it must be ruled explicitly in the policy record and the WARN text
changed — as shipped, the code and the operator contract disagree.

### F-2 — MAJOR — Read-error arm's best-effort posture write can launder an unreadable prior record (read fails, write succeeds)

**File:** `SuperGenius/src/transaction/PruneEligibility.cpp:742-749`

**Description:** On any `GetRaw` error other than `NOT_FOUND`, the arm logs,
calls `write_current_posture()` (line 748), and returns `UnreadableDisarm`.
If the read failed transiently (IO error, corrupt block in the read path,
temporary unavailability of one kind) while the subsequent `PutRaw` succeeds
on the same store, an existing archive-era record is **overwritten with the
current light posture** — the next boot reads `NoDowngrade` and arms,
identically to F-1 but through the arm whose entire purpose is
"unreadable ⇒ disarm". The arm's own doc rationale is self-contradictory: the
`write_current_posture` comment promises *"the prior record stands and
re-detects next boot"*, which is only true when the write **fails**. This is
the exact laundering the parse-failure arm (five lines below) refuses:
*"overwriting would launder an unreadable prior role through a single
reboot."*

Note the two sub-cases of a non-NOT_FOUND read error: (a) the record exists
but was unreadable — the write destroys evidence that must be preserved; (b)
the datastore is gone/null (`operation_canceled` during shutdown) — the write
fails anyway. In **no** case does the best-effort write help; in case (a) it
is harmful.

**Suggested fix:** delete the `write_current_posture()` call from this arm.
`NOT_FOUND` keeps its FirstRun write (a genuinely absent record must be
seeded); the parsed-prior arms keep theirs; only the
unknown-state-because-unreadable arm must not touch the record. Optionally
assert the no-write contract in a verdict-matrix leg (inject a read failure
that leaves the prior record intact).

### F-3 — MAJOR — The GeniusNode gate wiring has no automated enforcement; the policy record cites "GeniusNode source gates" that do not exist as tests

**File:** `SuperGenius/src/account/GeniusNode.cpp:5224-5292`; policy record
`.planning/workstreams/rocksdb-backup/notes/18-collectibility-policy-downgrade-interlock.md` §Evidence; plan item `18-02-PLAN.md:220`

**Description:** Every property that makes the interlock work at the wiring
level is currently pinned by nothing mechanical:

- the `CheckAndRewrite` call sitting **above** the `!pruning_config_.enabled`
  early-return (5249-5252) — load-bearing, because an archive-era node runs
  pruning-disabled and must still write its archive posture or every later
  downgrade is blind;
- the disarm gates sitting **between** the Light check (5253-5260) and the
  `TxPruner::New` arm (~5300);
- the once-per-process latch and the two WARN texts.

The new Tier-1 suite drives `CheckAndRewrite` and `TxPruner` **directly** — no
test constructs the gate, and if the entire interlock block in
`StartPruneTimerIfConfigured` were deleted, the full Phase-18 lane stays
green. This repo has an established source-gate mechanism for exactly this
class of ordering assertion (`EraseSurfaceGateTest` in
`crdt_erase_test.cpp:1053-1110` scans `GeniusNode.cpp` function bodies and
asserts source-order properties, e.g. `RealCycleIsPinnedToRealModeBeforeAnyErase`),
and `18-02-PLAN.md:220` lists "GeniusNode source gates: both WARN texts +
posture line + CheckAndRewrite call present; gate ordering above the enabled
early-return" as a verification item — but no such gate test was shipped, and
the policy record's §Evidence section presents "GeniusNode source gates" in a
list of test-derived evidence, overstating what exists. At best this was a
manual verification, which does not survive refactors.

**Suggested fix:** add an `EraseSurfaceGateTest`-style source gate:
extract `StartPruneTimerIfConfigured`'s body and assert (1) the
`CheckAndRewrite(` occurrence precedes the `!pruning_config_.enabled` return,
(2) both disarm WARN literals are present and precede the `TxPruner::New`
invocation, (3) the `role_fingerprint_checked_` latch token is present, and
(4) the tiered-light posture INFO literal exists in `LoadCrdtConfig`. Amend
the policy record's Evidence wording to match what is (and is not) mechanical.
This matters doubly while F-1 stands unfixed: the ordering that writes the
archive posture at all is the substrate the whole interlock rests on.

### F-4 — MINOR — Live smoke t2 verdict assertion is vacuous

**File:** `SuperGenius/test/src/crdt/cold_downgrade_live_smoke_test.cpp:713-719`

**Description:** The t2 leg's comment says *"The armed posture (ack present;
prev = the light posture the t1 check rewrote)"*, but the assertion is only
`ASSERT_TRUE( verdict.has_value() )` — it never pins `NoDowngrade`. Unlike
the Tier-1 t2 leg (`cold_downgrade_e2e_test.cpp:969-974`, which does
`EXPECT_EQ(NoDowngrade)`), this leg would stay green under any verdict
regression in the record semantics. The leg is dev-gated and advisory-tier,
hence MINOR.

**Suggested fix:** `EXPECT_EQ( verdict.value(), Verdict::NoDowngrade )` to
match the Tier-1 leg.

### F-5 — ADVISORY — Fingerprint record validation is weaker than the `/prune/blk` evidence discipline (empty/garbage-enum values parse as valid)

**File:** `SuperGenius/src/transaction/PruneEligibility.cpp:752-763`

**Description:** A zero-length value at the fingerprint key parses as a valid
all-defaults `RoleFingerprintRecord` (`node_type=0` = `Full`) → the predicate
fires `DowngradeUnacknowledged` → disarm (fail-closed, but the record is then
rewritten). An out-of-range `node_type` (e.g. 7) also parses and, because
`ReplicatesAllAccounts` is shaped `!= Light`, counts as a replicating prior →
disarm. Both directions are safe-by-construction (proto3 default `0` = Full =
downgrade source; garbage ≠ Light = replicating), which is a nice accidental
property — but the `/prune/blk` predicate explicitly treats zero-length rows
as `Malformed` (the `LookupPrunedBlockEntry` empty check, mirrored in the
globaldb lambda and the walk-gap test), and the fingerprint does not. The
asymmetry is survivable because every outcome lands on the disarm side; this
is a consistency/defense-in-depth note only. (An empty fingerprint row
arguably should be `UnreadableDisarm` with preservation, like the corrupt
arm.)

**Suggested fix (optional):** add `prior.value().empty()` and a
`node_type <= 2` range check to the corrupt arm so degenerate records take
the preserve-and-disarm path instead of relying on the default-value
coincidence.

### F-6 — ADVISORY — Ill-typed `downgrade_acknowledged` silently keeps `false`

**File:** `SuperGenius/src/transaction/PruneEligibility.cpp:112-119`

**Description:** `"downgrade_acknowledged": "true"` (string) is silently
ignored — the consent key stays `false` and a legitimately planned downgrade
keeps disarming every boot until someone notices. This matches the
`FromJSON` pattern of every sibling key (no warn anywhere for ill-typed
values), and the failure direction is safe (disarm, not arm), so this is
advisory. But for a **consent** key, an operator who believes they
acknowledged and keeps getting `ROLE DOWNGRADE DETECTED` WARNs has no signal
why; one warn on a present-but-ill-typed ack key would save that debugging
session.

**Suggested fix (optional):** log a warn when the key is present but not a
bool (key-scoped, not a second consent surface).

---

## What is solid

- The walk-gap exemption itself is tight: single-predicate consult at the
  exact gap site, counted-continue terminal-leaf semantics, per-pass reset
  beside the reclaimed accumulators, status/INFO surfacing with the field
  placed to keep existing tail-greps alive, and fail-closed controls in the
  red-first suite (LEG-1/LEG-2 + NoEvidence/Malformed/zero-baseline legs, and
  the repeat-pass identical-count idempotency check).
- The verdict-matrix legs genuinely pin the helper: FirstRun,
  DowngradeFire, AckArms, FullFires (A2), UnreadableDisarm-with-preservation,
  SamePosture, and the ack-key parse contract — on a real GlobalDB raw
  surface, seeded through the production builder, no hand-built keys.
- The t0→t3 timeline is a real composition (real CRDT Put, real erase path
  producing markers, structurally-held drainer proving no-re-drain the strong
  way, in-band exemption survival, below-link eviction + remote-backed
  serving, seals untouched, remote unchurned).
- The LEG M8 compose-matrix update is a correct adaptation: with the
  exemption, the walk completes where it used to abort, so the fixed point is
  now a genuine disposal fixed point and must be driven before the
  before-snapshot; `include_overlap=false` correctly matches the leg's
  no-detach posture.
- CMake registrations follow the audit's contract: `SGNS_COLD_STORAGE`-gated,
  labels Tier1/Tier1/Tier3 with matching `set_tests_properties` lines.

## Summary verdict

**CHANGES REQUESTED.** The 18-01 walk-gap exemption and its tests are in good
shape and ship-ready. The 18-02 interlock substrate is well-tested at the
helper level but has one critical consent-bypass (F-1: the record rewrite on
the unacknowledged arm makes the interlock a one-boot speed bump that any
unattended restart defeats, contradicting the WARN's own contract and the
phase's headline invariant), one MAJOR laundering path on the read-error arm
(F-2), and no mechanical enforcement of the load-bearing GeniusNode wiring
(F-3) — while the policy record cites source gates that were not shipped.
F-1's fix is small (skip the rewrite on the unack'd arm, mirroring the
corrupt arm), F-2's is one deleted call, and F-3 has an in-repo precedent
(`EraseSurfaceGateTest`) to copy; with those landed and a
second-unacked-boot test added, this phase's code would match the discipline
its own policy record claims.
