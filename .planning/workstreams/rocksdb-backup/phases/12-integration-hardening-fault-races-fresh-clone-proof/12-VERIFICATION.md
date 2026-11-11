---
phase: 12-integration-hardening-fault-races-fresh-clone-proof
workstream: rocksdb-backup
requirement: TEST-02
verdict: VERIFIED
date: 2026-11-10
status: passed
score: 4/4 success criteria verified
verification_method: goal-backward, evidence-based (no build/test execution per scope ruling; code artifacts, git history, committed evidence trio, and user-accepted CI run 42905264387 inspected directly)
---

# Phase 12 Verification — Integration Hardening, Fault Races & Fresh-Clone Proof

**Phase Goal:** The integration's trust claims hold under induced failure and reproducible builds — cross-actor races are proven safe, GC resurrection is counter-tested, outages soak without unbounded growth, and a fresh clone builds and passes Tier-1 on all three desktop platforms with cold storage ON

**Verified:** 2026-11-10 · **Verdict: VERIFIED** · UAT 17/17 PASS (user evidence ruling recorded in `12-UAT.md`)

---

## Per-Criterion Verification

### SC1 — Evict × serve × drain fault races under FaultController timing injection

| Evidence inspected | Detail | Status |
|---|---|---|
| `SuperGenius/test/src/crdt/cold_storage_fault_race_test.cpp` | Exists; **13 TEST_F cases counted** — exactly as claimed: `EvictServe_HalfWindowS3Fetch_ResolvesCidVerified` (:1009), `EvictServe_HotCleanupWindow_ReaderNeverTorn` (:1141), `EvictServe_RewarmAttachVsMark_NoLostBlock` (:1196), `EvictDrain_EligibilityVsDurabilityAdvance_NeverEvictsNonDurable` (:1282), `EvictDrain_DrainSnapshotVsHalfOne_NoEvictedBytesInDrain` (:1336), `ServeDrain_RemoteLockLatency_ColdFetchWithinBudget` (:1385), `Triple_GraceExpiryReachableAgain_CancelsKeepsBytes` (:1448), `Triple_DeleteBatchMidFlight_RedeliveryDedupDrainUnaffected` (:1517), `Evict_CancelVsCommitKnifeEdge_HeadsMutationBetweenRecheckAndHalfOne` (:1568), `Jitter_PairwiseSeededIterations_EndStateInvariants` (:1616), `SuiteEnd_AuditWalk_EveryCidInLegalState` (:1694), `ZeroBlacklistWrites_AfterAllScenarios` (:1780), `CorruptAssertionHasTeeth_ByteFlipStillCorrupt` (:1818) | ✓ |
| Zero-blacklist teeth | `ZeroBlacklistWrites_AfterAllScenarios` asserts `PEER_BLACKLISTED` never fired (:1799); in-matrix assertion "storage faults classify cold - never PEER_BLACKLISTED" (:1426) | ✓ |
| Byte-flip control | `CorruptAssertionHasTeeth_ByteFlipStillCorrupt` flips the last copy and asserts `COLD_STORAGE_CORRUPT` surfaces (:1833-1837) — the zero-Corrupt claims have teeth | ✓ |
| Jitter repro knobs | `SGNS_RACE_JITTER_SEED` / `SGNS_RACE_JITTER_ITERS` read at :1618-1619 (defaults 20261028 / 200) | ✓ |
| Suite registration | `SuperGenius/test/src/crdt/CMakeLists.txt` :213-225, `LABELS "Tier1"` | ✓ |
| Commits | `e2fb50709` (tracer), `0b3a4a46f` (matrix) both in SuperGenius dev_blockstore history, 2026-10-28 | ✓ |

**SC1: VERIFIED** — race matrix, audit walk, zero-blacklist, and byte-flip control all present, substantive (real assertions, not stubs), registered, and green in the user-accepted CI lane.

### SC2 — Resurrection counter-test (delete → GC → re-deliver ⇒ absent everywhere)

| Evidence inspected | Detail | Status |
|---|---|---|
| `SuperGenius/test/src/crdt/cold_storage_resurrection_test.cpp` | Exists with **exactly the three claimed legs**: `Resurrect_MarkerPresent_DedupBlocksReintegration` (:530), `Resurrect_TrimmedMarker_TombstoneDominanceKeepsValueAbsent` (:596), `Resurrect_FullWire_TwoGlobalDBRedeliveryStaysDeleted` (:692) | ✓ |
| Substance | 68 assertion matches — marker-dedup leg asserts zero re-journal + `ValueVisible` false (:575-580); trimmed-marker leg asserts tombstone dominance post-`TrimDisposed` (:609-633); full-wire leg drives two real GlobalDBs over in-process gossip, proves background GC eviction via `GetColdStorageStatus` disposed markers, re-broadcasts, asserts zero S3 Gets / zero pending / value absent on **both** nodes (:896-963) | ✓ |
| Production defect fix | `SuperGenius/src/crdt/impl/crdt_set.cpp` :399-455 — `InElemsNotTombstoned` empty-enumeration branch now tomb-aware: no elems + tombstones ⇒ **not in set** (the resurrection defect); no elems + no tombstones ⇒ in-set (preserves the `SetValue`-only contract). Detailed in-code comment documents both failure modes. Commits: `f35895fca` (12-01, failing-first) + `de9175923` (12-03 tomb-aware refinement after the blanket empty→false broke `CrdtSetTest.TestSetValue`) — both in history | ✓ |
| Suite registration | CMakeLists.txt :236-267, `LABELS "Tier1"` | ✓ |
| Commits | `f35895fca`, `d8a7371c9` in history, 2026-10-28 | ✓ |

**SC2: VERIFIED.** Note for the record: the fix's final form is the **tomb-aware** refinement (`de9175923`), slightly stronger than the 12-01 summary's blanket "empty → not-in-set" description — the end state satisfies the resurrection requirement without breaking the local-value contract.

### SC3 — s3d-unavailable soak: bounded journal, alarm firing, publishes continue; teardown-under-load joins; peer cold-fetch within budget

| Evidence inspected | Detail | Status |
|---|---|---|
| `SuperGenius/test/src/crdt/cold_storage_soak_test.cpp` | Exists with **exactly the four claimed TEST_F**: `IterationSoak_OutageThenRecovery_NoMultiplyWatermarkDrain` (:427), `Teardown_CleanStopUnderFullActorMix_BoundedAndOrdered` (:556), `Teardown_KillSurrogate_ReopenReconcilesNoDuplication` (:667), `PeerColdFetch_InjectedLatency_StaysWithinRewarmBudget` (:865). Tier1-registered (:275-287) | ✓ |
| `SuperGenius/test/src/crdt/cold_storage_wallclock_soak.cpp` | Exists; env gates `SGNS_COLD_STORAGE_SOAK_ENABLE` (:300, loud labelled skip when unset), `_DURATION_MIN` (:309), `_RESUME` (:308); `kill-window` (:435) and `RECONCILIATION` (:320-378) output lines match the captures. Registered **Tier3 only, deliberately no Tier1 label** (CMakeLists.txt :290-306) | ✓ |
| `12-soak-evidence/README.md` | Substantive runbook: binary/workdir/env-gate table, run procedure, kill-9 procedure (`Stop-Process -Force` / `kill -9`), and the D-06 assertion contract the captures must demonstrate | ✓ |
| `12-soak-evidence/run-capture.md` | Kill at 18:51:42 `[kill-window] outage + pending=170`, watermark Critical, `Stop-Process -Id 42892 -Force`; resume reconciliation journal 2162 → remote 2162 **no loss, no duplication**; run-4 verification leg on the fixed binary `[ PASSED ]` with 19975 == 19975. Run-2 close-out off-by-one honestly documented (binary race, fixed same session, reconciliation evidence unaffected) | ✓ |
| `12-soak-evidence/status-capture.txt` | Watermark/pending time series: None → Critical transitions, kill-window lines, 60 s held-watermark heartbeats ×4, six phase cycles, post-recovery drain to pending=0 / watermark=None | ✓ |
| Commits | `53efd15a1`, `7845db4f9`, `7209add43`, `429b3e7e8` all in SuperGenius history, 2026-10-28 | ✓ |

**SC3: VERIFIED** — bounded-journal is demonstrated as the no-multiply invariant (pending never exceeds distinct published CIDs; journal is alarm-only by design, documented in the README), alarm firing and publish continuity evidenced across the captures, and all four teardown/cold-fetch behaviors are Tier-1 tests that ran green in CI.

### SC4 — Fresh-clone proof: pushed commits only, three platforms, cold storage ON, tier-label audit

| Evidence inspected | Detail | Status |
|---|---|---|
| `12-FRESH-CLONE-CHECKLIST.md` | Status COMPLETE 2026-11-10. Records run **42905264387** (workflow_dispatch, head `9994718ce` — verified as SuperGenius dev_blockstore HEAD with `origin/dev_blockstore` and tag `test_coldstorage` on it), thirdparty tag `test_coldstorage_rtti` (target 4a97e95), `run_tests=true`, `cold_storage=true`, **all 15 jobs success**: Windows Release **153/153**, Linux x86_64 Release **152/152**, OSX Release **155/155**, `-DSGNS_COLD_STORAGE=ON` and `Downloading thirdparty from tag: test_coldstorage_rtti` log-verified per leg. Two fail-closed `git ls-remote` SHA tables (2026-10-28 and final 2026-11-10) | ✓ |
| Header-install change | `thirdparty/sgns-blockstore/CMakeLists.txt` :80-82 — `install(FILES src/InMemoryS3Client.hpp src/InMemoryS3AdminClient.hpp DESTINATION "${CMAKE_INSTALL_INCLUDEDIR}/sgns-blockstore")` with rationale comment. Local HEAD = `ee0266b` "feat: install test-fake headers … SC4 fresh-clone fix" = `origin/main` = the exact claimed commit. **Location note:** the rule lives in the repo-root `CMakeLists.txt` (installing from `src/`), not `src/CMakeLists.txt` — functionally identical to the checklist's quoted rule; the source-tree `include/sgns-blockstore/` deliberately does not carry the fakes (they install into the prefix). Payload proof: checklist tar listing (`build/Windows/Release/sgns-blockstore/include/sgns-blockstore/InMemoryS3Client.hpp`, 2 hits) + 10 SuperGenius cold suites compiling against `<sgns-blockstore/InMemoryS3Client.hpp>` + the CI fresh-clone legs building everything from the tarball alone | ✓ |
| Tier-label audit | `SuperGenius/test/CMakeLists.txt` :20-23 registers `tier1_static_audit` with `LABELS "Tier1"`; implementation `SuperGenius/test/tier1_audit_check.cmake`. Checklist records it **green in CI for the first time**: Linux leg Test #15/152 Passed (0.03 s), included in every leg's 100% count; local pre-check proved the teeth (scratch-removing a LABELS line failed the audit) | ✓ |
| CI cold-storage surfaces | `SuperGenius/.github/workflows/cmake.yml` — `cold_storage: [OFF, ON]` matrix (:186) with permanent ON legs appending `-DSGNS_COLD_STORAGE=ON` (:266, :274, :279). `SuperGenius/.github/workflows/build-release-tags.yml` — `cold_storage` dispatch input (:83) driving desktop-gated `COLD_STORAGE_ARGS` append (:218); `thirdparty_tag` / `run_tests` inputs present; configure lines carry `$COLD_STORAGE_ARGS` (:717-739) | ✓ |
| UAT | `12-UAT.md` 17/17 pass, zero issues; user ruling (2026-11-10) accepts run 42905264387 as evidence for all ctest-covered checkpoints in lieu of local re-runs; non-CI checkpoints (13, 15, 16, 17) verified against committed artifacts in-session | ✓ |

**SC4: VERIFIED.**

---

## Goal-Backward Judgment

Working backwards from the goal's four trust claims:

1. **"Cross-actor races are proven safe"** — the 13-case barrier-driven matrix with zero-Corrupt/zero-lost/zero-blacklist assertions and a byte-flip control exists, is deterministic-by-construction (WindowGate + seeded jitter), and ran green in the accepted CI lane on all three platforms. TRUE in codebase + evidence.
2. **"GC resurrection is counter-tested"** — the three-leg counter-test covers marker-dedup, trimmed-marker tombstone dominance, and full-wire re-delivery, AND it caught and closed a real production resurrection defect (`InElemsNotTombstoned`), fixed failing-first then refined tomb-aware. TRUE.
3. **"Outages soak without unbounded growth"** — no-multiply invariant, watermark alarm/heartbeat/drain evidenced in committed captures; true kill-9 + resume reconciliation 2162==2162 and a clean verification leg; teardown-under-load and peer cold-fetch budget are Tier-1 green. TRUE.
4. **"Fresh clone builds and passes Tier-1 on all three desktop platforms with cold storage ON"** — run 42905264387 from pushed commits only (fail-closed SHA tables), consuming the release tag whose tarball now installs the test fakes, 153/153 + 152/152 + 155/155 with the ON flag log-verified per leg, and the tier-label audit green inside the lane. TRUE.

Task completion and goal achievement coincide here: the evidence is not SUMMARY narration — the test files, assertions, fix, install rule, workflow surfaces, and commits were each inspected directly, and the runtime claims rest on the user-accepted CI run plus the committed soak evidence trio.

## Gaps and Caveats (non-blocking)

1. **Deferred hardening signal (recorded, rides forward):** soak-scale GC eviction-storm crash (~2000 marks, nondeterministic 0xC0000005, retention age ~1 ms shape) — mitigated in-suite (retention ages held past the soak window), explicitly recorded in `12-02-SUMMARY` as deferred to a hardening follow-up. No recovery claim depends on evictions at soak scale.
2. **Permanent cmake.yml ON-leg baseline pending merge (topology, not defect):** `dev_blockstore` pushes don't trigger the develop CI workflow; the D-02a regression net activates at merge. The tag-build legs prove the identical configure (same `COLD_STORAGE_ARGS` append, same artifact consumption). Documented in the checklist.
3. **Precision notes (no action):** (a) the fake-header install rule lives in sgns-blockstore's **root** `CMakeLists.txt` installing from `src/`, not in `src/CMakeLists.txt`; (b) the resurrection fix's final form is the `de9175923` tomb-aware refinement, which `12-03-SUMMARY`'s key-files list does not mention (the commit message and in-code comment do); (c) run-2 soak close-out off-by-one — honestly documented, fixed, verification leg clean.
4. **Housekeeping (stale metadata, not evidence defects):** ROADMAP Phase 12 header still reads "Plans: 2/3 plans executed" while all three plans are checked and closed; STATE.md progress table rows show 0/N per phase though frontmatter records 21/21 complete. Worth a tidy at complete-milestone.

## Final Verdict

All four success criteria of TEST-02 Phase 12 are backed by committed, inspectable evidence; the phase goal's trust claims hold in the codebase.

**VERIFICATION: PASSED**
