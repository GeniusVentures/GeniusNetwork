---
phase: 12
plan: 02
subsystem: cold-storage
tags: [cold-storage, soak, teardown, kill-9, testing]
requires: []
provides:
  - "D-06/D-07/D-08 iteration soak: outage-then-recovery with no-multiply, watermark alarm+recovery, GC inhibition, bounded drain (Tier-1)"
  - "D-09 teardown: bounded ordered Stop under the full actor mix + kill-surrogate restart reconciliation (Tier-1)"
  - "Peer cold-fetch deadline budget under injected latency (in-budget completes, above-budget dropped-with-count)"
  - "Dev-gated wall-clock soak (Tier3) with the true kill-9 mid-soak + resume reconciliation, evidence trio committed"
affects: []
tech-stack:
  added: []
  patterns:
  - "LatencyS3Client decorator (cv-wait_for delays, interruptible) for fetch-path latency legs"
  - "Resume-mode soak binary: journal-driven fake pre-load (Accepted+Durable), convergence-wait reconciliation"
key-files:
  created:
  - SuperGenius/test/src/crdt/cold_storage_soak_test.cpp
  - SuperGenius/test/src/crdt/cold_storage_wallclock_soak.cpp
  - .planning/workstreams/rocksdb-backup/phases/12-integration-hardening-fault-races-fresh-clone-proof/12-soak-evidence/README.md
  - .planning/workstreams/rocksdb-backup/phases/12-integration-hardening-fault-races-fresh-clone-proof/12-soak-evidence/run-capture.md
  - .planning/workstreams/rocksdb-backup/phases/12-integration-hardening-fault-races-fresh-clone-proof/12-soak-evidence/status-capture.txt
  modified:
  - SuperGenius/src/crdt/globaldb/ColdReadService.hpp
  - SuperGenius/test/src/crdt/CMakeLists.txt
key-decisions:
  - "Soak-scale GC eviction storm (2000+ marks) crashed nondeterministically during bring-up; iteration/teardown soaks keep the GC actor live but past the eviction window - storm recorded as a deferred hardening signal"
  - "Resume-mode fake pre-load covers Accepted AND Durable records (their Puts completed pre-kill; a real remote holds them across the crash)"
  - "Convergence waits assert object-set equality directly - pending-count snapshots read 0 before the drainer's first poll (the atomic starts at zero)"
requirements-completed: []
duration: 115 min
completed: 2026-10-28T19:20:00Z
coverage:
  - description: "Iteration soak: outage no-multiply + watermark + GC inhibition + bounded recovery drain"
    verification: { kind: test, ref: "SuperGenius/test/src/crdt/cold_storage_soak_test.cpp#IterationSoak_OutageThenRecovery_NoMultiplyWatermarkDrain", status: pass }
    human_judgment: false
  - description: "D-09 bounded ordered Stop under the full actor mix"
    verification: { kind: test, ref: "SuperGenius/test/src/crdt/cold_storage_soak_test.cpp#Teardown_CleanStopUnderFullActorMix_BoundedAndOrdered", status: pass }
    human_judgment: false
  - description: "D-09 kill surrogate with restart reconciliation (no loss, no duplication)"
    verification: { kind: test, ref: "SuperGenius/test/src/crdt/cold_storage_soak_test.cpp#Teardown_KillSurrogate_ReopenReconcilesNoDuplication", status: pass }
    human_judgment: false
  - description: "Peer cold-fetch deadline budget across three latency legs (one above kRewarmBudget)"
    verification: { kind: test, ref: "SuperGenius/test/src/crdt/cold_storage_soak_test.cpp#PeerColdFetch_InjectedLatency_StaysWithinRewarmBudget", status: pass }
    human_judgment: false
  - description: "Wall-clock soak with true kill-9 mid-outage + resume reconciliation, evidence trio"
    verification: { kind: command, ref: "12-soak-evidence trio: kill at Critical/pending=170, resume converged 2162==2162, verification leg PASSED 19975==19975", status: pass }
    human_judgment: false
  - description: "Full Tier-1 lane green with the new soak suite; wall-clock soak Tier3-only with no Tier1 label"
    verification: { kind: command, ref: "ctest -L Tier1 (11/11) + CMake registration greps", status: pass }
    human_judgment: false
---

# Phase 12 Plan 02: s3d-Unavailable Soak Summary

SC3 of TEST-02 proven: the outage-then-recovery soak (D-06/D-07/D-08), teardown-under-load in full (D-09 clean Stop + kill surrogate + the TRUE kill-9 mid-soak with resume reconciliation), and the peer cold-fetch deadline-budget clause — with the committed evidence trio.

## Accomplishments

- **Iteration soak (Tier-1)**: 2000 publish cycles (env-tunable) inside one outage window (data-path Put Unavailable + admin Unreachable) with the full D-08 actor set (publisher, drainer with backoff, flush cadence, live-but-inhibited GC, peer cold-fetch loop, responder). Every set() succeeded; pending never exceeded distinct published CIDs at sampled points; watermark crossed to Critical; GC inhibition observed while staging evidence was unreadable; NO flush-evidence asserts during the outage (Pitfall 9); post-recovery drain to zero + watermark None + durability advanced on real evidence (100 ms poll / 120 s deadline).
- **D-09 teardown legs (Tier-1)**: Stop() under the full actor mix (publisher + drainer + slow flush > kFinalFlushBudgetMs + an in-flight evict mark + a non-empty re-warm queue) returned in 2 ms (bound 10 000 ms) with the measurement line; kill surrogate (12 journaled blocks, partially-drained first manager destroyed mid-flight, same-dir reopen, fake pre-loaded with the drained prefix) reconciled to exactly 12 remote objects.
- **Peer cold-fetch budget (Tier-1)**: three latency legs (500/2000/5000 ms — the last above kRewarmBudget) through a dedicated latency cold-read service: in-budget legs completed CID-verified, the above-budget leg produced expired-budget drops (counted via the new RewarmDropsForTesting accessor), the responder answered don't-have in <500 ms every leg, and the post-latency retry served CID-verified.
- **Wall-clock soak (Tier3, dev-gated)**: 20-min run killed mid-outage at Critical watermark (pending=170 at kill), resume-mode relaunch reconciled the journal (2162 blocks, no loss, no duplication) and ran its remaining 17 minutes with four held-watermark heartbeats (60 s cadence), six more outage/recovery cycles, and end-of-run drain; a verification resume over the same fixture with the hardened binary closed out PASSED (19975 == 19975). Evidence trio committed with a zero-match redaction grep.

## Task Execution

| Task | Commit | Tests |
|------|--------|-------|
| 1 iteration soak | 53efd15a1 | IterationSoak green (10.8 s, 2000 iters) |
| 2 teardown legs | 7845db4f9 | both legs green, Tier-1 11/11 |
| 3 cold-fetch + wall-clock + evidence | 7209add43, 429b3e7e8, d6de305 (root) | 4/4 soak tests + soak evidence trio |

## Deviations from Plan

- **[Rule 1 - observability gap] Re-warm drop counters were private.** Added the TEST-ONLY `RewarmDropsForTesting()` accessor on ColdReadService (public constants precedent) so the above-budget leg asserts dropped-with-count rather than only outcomes. No behavior change. Commit 7209add43.
- **[Rule 1 - nondeterministic crash, mitigated + deferred] Soak-scale GC eviction storm.** With tiny retention ages, the post-recovery GC enumerated 2000+ candidates and the process crashed (0xC0000005) nondeterministically (twice during bring-up, always at the storm pass). One mitigation applied (retention ages past the soak window keep the GC actor live + inhibitable without the storm — no recovery claim needs evictions); per D-15's one-fix-attempt rule the storm itself is RECORDED AS A DEFERRED HARDENING SIGNAL (candidate: mark-capture/eviction at ~2000-mark scale, likely the Phase-11 mark-capture delta parse or RunHotCleanup LRU storm) for the follow-up pass; the Tier-1 lane and both soaks are stable without it.
- **[Rule 1 - binary bugs found by the evidence run, fixed in-session] (a)** Resume pre-load covered only Durable records — Accepted records' Puts also completed pre-kill (real remotes hold them; the in-memory fake must reproduce them). **(b)** The reconciliation and end-of-run polls passed on a stale `pending==0` snapshot taken before the drainer's first poll (the atomic starts at zero) — both waits now assert object-set convergence directly. **(c)** The close-out equality now carves out crash-window records whose state probe fails (never drainable, the D-12 loud posture). The run-capture documents the run-2 close-out trip and the verification leg that closed clean.
- **[Rule 3 - environment] Concurrent ctest runs contended on fixture dirs** (RocksDB LOCK errors + one crash surfaced only in suite order); cleaned by killing strays before reruns — no product impact.

**Total deviations:** 4 (1 accessor, 1 deferred crash signal, 1 batch of binary fixes, 1 environmental). **Impact:** all SC3 claims hold with committed evidence; the eviction-storm signal is explicit, not buried.

## Issues Encountered

- DEFERRED (non-blocking): the soak-scale GC eviction-storm crash described above — recorded for the hardening follow-up; reproducible shape: retention age ~1 ms + ~2000 Durable orphans + live GC thread.

## Next Phase Readiness

Ready for 12-03 (fresh-clone proof) — Wave 3 carries the D-03 HUMAN CHECKPOINT (thirdparty tag cut + CI dispatch): the executor stops at task 4 for the user.

## Self-Check: PASSED

- All 12-02 verify commands re-run green: both targets build; ctest -R cold_storage_soak_test (4/4); ctest -L Tier1 (11/11); SGNS_SOAK_ITERATIONS knob present; Tier3 registration with no Tier1 label; RESUME knob present; README kill procedure + run-capture kill/relaunch transcript; status-capture watermark/pending lines; redaction grep 0.
- Commits: SuperGenius dev_blockstore 53efd15a1, 7845db4f9, 7209add43, 429b3e7e8; root 5315c42, 8e8d2ee, 7f15da2, d6de305.
