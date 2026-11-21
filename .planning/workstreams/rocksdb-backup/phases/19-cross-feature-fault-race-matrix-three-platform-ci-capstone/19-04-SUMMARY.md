---
plan: 19-04
phase: 19-cross-feature-fault-race-matrix-three-platform-ci-capstone
completed: 2026-11-20
requirements: [TEST-02]
status: complete
---

# Plan 19-04 Summary: The Matrix Closed — X10 (audit + teeth + baseline) + X11 (the full-wire leg)

## What Was Built

The fault-race matrix is complete. **X10** closes it: the suite-end audit walks the legal-state trichotomy (hot-present / cold-resident-without-evidence / evidenced-absent — each resolved through the fixture store surfaces with zero-S3 or terminal-refusal observables), a zero-CID empty baseline proves never-healthy-by-omission works both ways, the byte-flip teeth leg (the v1.1 `CorruptAssertionHasTeeth_ByteFlipStillCorrupt` pattern verbatim) proves flipped cold bytes are refused `COLD_STORAGE_CORRUPT`, and the counter-teeth leg proves the `VALUE_PRESENT_INVARIANT_VIOLATION` class is loud: the sanctioned `/prune/tx` marker (`WritePrunedEntryForTest`) written while the value survives surfaces the verdict and fails `CanRestoreElement` closed. **X11** is the ONE full-wire leg (D-06): two real GlobalDBs over the real gossip wire (the v1.1 resurrection leg-3 recipe verbatim), hermetic cold on B — B's evidenced history is refused terminally end-to-end (zero cold Gets, zero re-journal, never a peer fall-through onto the wire), and the failover drive without evidence serves CID-verified bytes from A over the wire. The suite now hosts the complete X1..X11 set 19-05 renders and the lanes prove.

## Key Changes

### Test (one file, +579 lines over two commits)

- `SuperGenius/test/src/crdt/cold_cross_feature_fault_race_test.cpp`:
  - `Cross_SuiteEnd_AuditWalkAndCounterTeeth` (X10, Task 1 `21b74aba4`): audit leg (trichotomy one-per-class with per-class observables), the audit×GC coherence observation (the evidenced-absent class is an exempted LEAF to the GC walk — `gc_last_pass_exempted ≥ 1`, never an abort), the empty baseline (empty-topic walk all-counters-zero + empty-store pass zero/zero), byte-flip teeth (case-local object), counter teeth (gw tx world).
  - `Cross_FullWire_RefusalFailoverUnderConcurrentErase` (X11, Task 2 `b17787b0e`): two pubsub hosts on separate io contexts, two GlobalDBs (A cold OFF, B cold ON with the `TimingS3Client`-wrapped hermetic fakes), propagation prologue (durable ≥ 2 on B, value dead both sides), the refusal leg (B's `/prune/blk` row + private-topic cid + rebroadcast → terminal refusal, zero S3 after quiesce), the failover leg (no evidence → peer leg → A serves over the wire → `y-value` arrives CID-verified), status-dump-on-exhaustion on both nodes, the recipe's teardown order.
  - `EncodeCidAnnouncement` re-declared in-file (the recipe's shape — `EncodeBroadcastStatic` is protected), `crdt/proto/bcast.pb.h` added to the include block (19-01's resurrection link set carried the rest).

## Key Files

**Modified:** `SuperGenius/test/src/crdt/cold_cross_feature_fault_race_test.cpp` (+227 then +352)
**Production:** zero diff — no fix-forward needed; every find was fixture-level.

## Finds (fixture-level)

1. **The baseline-ordering find (X10 run1):** the empty baseline must run BEFORE the trichotomy seeding — the audit's own evidenced-absent cid legitimately counts as an exempted gap to the GC walk (`exempted=1`), which is itself the audit×GC coherence property (now asserted explicitly rather than tripped over).
2. **The drain-noise find (X11 run1):** B's propagation drain leaves trailing S3 traffic that pollutes the refusal leg's zero-Get attribution — quiesce (`pending_upload_count == 0` + a 300 ms settle) before sampling `gets_before`.
3. **The address-resolution race (X11 run1):** A's `PubSubBroadcasterExt::Broadcast` intermittently fails with "No addresses found for broadcasting" — both rebroadcasts are bounded-retry through `PollUntil` (instrument, never bump).

## Red-First / Stability Evidence Trail

1. **x10-run1:** the baseline-ordering find (`gc_last_pass_exempted` 1-vs-0).
2. **x10-run2 (knob-OFF, full suite):** **16/16 PASSED** — the X1..X10 set green.
3. **x10-run3 (knob-ON):** RED-OBSERVED with **X10 OK** (the teeth legs are their own teeth, NOT knob-gated — the plan's explicit requirement) and the 9 fault-arm carriers still firing.
4. **x10-run4:** Tier-1 **20/20**.
5. **x11-run1:** the drain-noise + address-race finds.
6. **x11-run2:** X11 alone green (2.6 s).
7. **Wire-stability smoke:** **3 consecutive full-suite green runs** (20.8 s / 20.9 s / 21.8 s) — the promotion contract's local stability assumption holds.
8. **Tier-1 after X11:** **20/20, exit 0**.
9. Scratch evidence: `.gsd/x10-run*.txt`, `.gsd/x11-run*.txt`, `.gsd/x11-tier1.txt` (untracked scratch, the suite convention).

## Verification Results

- Build: exit 0 at both commits (the pre-existing C4834 warning, line-shifted only).
- Suite knob-OFF: **16/16** (X1..X11 complete set), ×3 consecutive.
- Suite knob-ON: RED-OBSERVED (9 fault-arm carriers) with **X10 green under the knob** (teeth ungated).
- Full Tier-1 lane: **20/20, exit 0**.
- Source gates (Task 1): X10 name 2 (≥1); the X1..X10 case set 26 (≥10); src diff 0. (Task 2): X11 name 4 (≥1); `SGNS_CROSS_RACE_FULLWIRE_ENABLE` 11 (≥1); `GossipPubSub` usage present; src diff 0.

## Deviations from Plan

**[Rule 1 — X11's A5 invocation (recorded, not silent)]:** the plan's A-side concurrent-erase-mid-serve leg requires per-node tx stacks the leg-3 recipe does not carry; per the flagged assumption's own relief, the wire leg lands the two claims the recipe extends to cleanly (refusal terminality on the wire + failover-serves-unevidenced), and the dropped claim — the gate defers under an in-flight serve, no lost last copy — is already crossed hermetically with teeth by X3-B leg 2 and X8-B (19-02). Recorded here and in the commit message.

**[Rule 1 — X11's refusal-leg state]:** the evidenced-but-never-held cid (A's private-topic put + B's policy row) is the drivable honest input for the wire consult: the recipe's GC-eviction path retains the seal marker, whose D-02 guard short-circuits the receive lane before any consult — the evidence-consult refusal is only reachable for a never-sealed cid. The injection is the suite's established control grammar (the guard's input state induced; the guard's behavior the claim).

**[Rule 1 — X11 rebroadcast resilience]:** bounded-retry broadcasts against the address-resolution race (find 3) — the plan's "no deadline widening" discipline preserved (the retry is instrumented and bounded, the deadlines unchanged).

**Total deviations:** 3 (all recorded-design). **Impact:** none beyond plan intent — the matrix's must-have truths are all asserted somewhere in X1..X11.

## Issues Encountered

None open. The X11 promotion evidence itself (two consecutive green dispatches of build-release-tags.yml, three platforms) is 19-05's checkpoint per the planner ruling.

## Self-Check: PASSED

- Both tasks executed and committed atomically (`21b74aba4`, `b17787b0e`).
- All acceptance criteria re-run and passing (see Verification Results; the 3-run smoke recorded).
- SUMMARY created in plan directory; STATE/ROADMAP updated by the orchestrator close-out.
