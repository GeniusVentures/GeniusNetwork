---
status: complete
phase: 12-integration-hardening-fault-races-fresh-clone-proof
source: [12-01-SUMMARY.md, 12-02-SUMMARY.md, 12-03-SUMMARY.md]
started: 2026-11-10T23:50:00Z
updated: 2026-11-11T00:05:00Z
---

## Current Test
<!-- OVERWRITE each test - shows where we are -->

[testing complete]

### Evidence ruling (user, 2026-11-10)

User accepted SuperGenius Tag Build run 42905264387 (head 9994718ce,
thirdparty tag `test_coldstorage_rtti`, run_tests=true, cold_storage=true,
all 15 jobs success; Windows Release 153/153, Linux x86_64 Release 152/152,
OSX Release 155/155 — 100% on every leg) as the evidence for all
ctest-covered checkpoints in lieu of local re-runs. Every cold-storage
suite (fault_race, resurrection, soak, config_gate, tier1_static_audit)
ran inside that lane with `-DSGNS_COLD_STORAGE=ON` log-verified per leg.
Non-CI checkpoints (13, 15, 16, 17) were verified directly against the
committed artifacts during this session.

## Tests

### 1. Fault-Race Tracer — Evict×Serve Half-Window Crossing
expected: In your Windows Debug build tree, `ctest -R cold_storage_fault_race_test` passes, including EvictServe_HalfWindowS3Fetch_ResolvesCidVerified: GC parked in the HALF1-committed/HALF2-not-started window while the serve's S3 fetch is held mid-flight; releasing the fetch first resolves the block CID-verified with the original bytes; end state is disposed-with-remote-copy; a second read issues zero S3 Gets.
result: pass
evidence: "CI run 42905264387 (user-accepted): suite ran in-lane, 100% per leg"

### 2. D-11 Race Matrix — Nine Crossings + Knife Edge
expected: `cold_storage_fault_race_test` runs all 13 TEST_F cases green deterministically (barrier-driven, no fixed sleeps): hot-cleanup-window reader never torn; re-warm attach vs mark never loses a block; non-Durable never evicted; drain snapshot never holds evicted bytes; remote-lock latency fetch stays within the 4 s re-warm budget with honest COLD-classified decline; reachable-again cancel keeps bytes; delete-batch mid-flight re-delivery drops at the marker; cancel-vs-commit knife edge keeps the value whole-never-torn.
result: pass
evidence: "CI run 42905264387 (user-accepted): suite ran in-lane, 100% per leg"

### 3. D-12 Audit Walk + Zero-Blacklist + Byte-Flip Teeth
expected: `SuiteEnd_AuditWalk_EveryCidInLegalState` passes — every published CID ends in exactly one legal state, zero storage-attributed blacklist writes, and the byte-flip control keeps the zero-Corrupt assertions honest (a flipped byte is detected by the suite's own control).
result: pass
evidence: "CI run 42905264387 (user-accepted): suite ran in-lane, 100% per leg"

### 4. Seeded Jitter Legs (SGNS_RACE_JITTER_SEED/_ITERS)
expected: `Jitter_PairwiseSeededIterations_EndStateInvariants` passes with the default 200 iterations; setting SGNS_RACE_JITTER_SEED / SGNS_RACE_JITTER_ITERS makes a run reproducible (same seed → same deterministic outcome).
result: pass
evidence: "CI run 42905264387 (user-accepted): suite ran in-lane, 100% per leg"

### 5. SC2 — Marker-Present Dedup Blocks Reintegration
expected: `cold_storage_resurrection_test` passes Resurrect_MarkerPresent_DedupBlocksReintegration — 25 pubsub-path re-deliveries of a disposed CID drop at the disposed marker with zero S3 Gets and zero re-journal.
result: pass
evidence: "CI run 42905264387 (user-accepted): suite ran in-lane, 100% per leg"

### 6. SC2 — Trimmed-Marker Tombstone Dominance
expected: `Resurrect_TrimmedMarker_TombstoneDominanceKeepsValueAbsent` passes — after TrimDisposed erases the dedup line, the merge runs (re-journals per the documented contract) but tombstone dominance keeps the deleted value absent.
result: pass
evidence: "CI run 42905264387 (user-accepted): suite ran in-lane, 100% per leg"

### 7. SC2 — Full-Wire Two-GlobalDB Re-Delivery Stays Deleted
expected: `Resurrect_FullWire_TwoGlobalDBRedeliveryStaysDeleted` passes hermetically (zero network) — over the real in-process libp2p+graphsync gossip wire with receiver cold storage ON, background GC eviction is proven via GetColdStorageStatus disposed markers; node-1's re-broadcast of the original CID announcement drops on the receiver with zero S3 Gets and zero pending; the value is absent on both nodes.
result: pass
evidence: "CI run 42905264387 (user-accepted): suite ran in-lane, 100% per leg"

### 8. Full Tier-1 Lane Green Fail-Closed With Both New Suites
expected: `ctest -L Tier1` in the Windows Debug tree passes (11/11 with cold storage compiled ON) — the pre-existing suites plus cold_storage_fault_race_test, cold_storage_resurrection_test, and cold_storage_soak_test, with no new corrupt/blacklist failures.
result: pass
evidence: "CI run 42905264387 (user-accepted): full ctest suite exceeded the Tier-1 lane — all tests, cold storage ON, 100% per leg"

### 9. Iteration Soak — Outage→Recovery No-Multiply
expected: `IterationSoak_OutageThenRecovery_NoMultiplyWatermarkDrain` in cold_storage_soak_test passes (~11 s, 2000 iterations default): every set() succeeds inside the outage window, pending never exceeds distinct published CIDs at sampled points, watermark crosses to Critical, GC inhibition observed while staging evidence is unreadable, no flush-evidence asserts during the outage, and post-recovery the drain reaches zero + watermark None + durability advances on real evidence.
result: pass
evidence: "CI run 42905264387 (user-accepted): suite ran in-lane, 100% per leg"

### 10. D-09 — Bounded Ordered Stop Under Full Actor Mix
expected: `Teardown_CleanStopUnderFullActorMix_BoundedAndOrdered` passes — Stop() under publisher + drainer + slow flush (> kFinalFlushBudgetMs) + an in-flight evict mark + a non-empty re-warm queue returns well within the 10,000 ms bound with the measurement line logged.
result: pass
evidence: "CI run 42905264387 (user-accepted): suite ran in-lane, 100% per leg"

### 11. D-09 — Kill-Surrogate Restart Reconciliation
expected: `Teardown_KillSurrogate_ReopenReconcilesNoDuplication` passes — 12 journaled blocks, partially-drained first manager destroyed mid-flight, same-dir reopen with the fake pre-loaded drained prefix reconciles to exactly 12 remote objects (no loss, no duplication).
result: pass
evidence: "CI run 42905264387 (user-accepted): suite ran in-lane, 100% per leg"

### 12. Peer Cold-Fetch Deadline Budget (three latency legs)
expected: `PeerColdFetch_InjectedLatency_StaysWithinRewarmBudget` passes — the 500/2000 ms legs complete CID-verified; the 5000 ms leg (above kRewarmBudget) produces expired-budget drops counted via RewarmDropsForTesting; the responder answers don't-have in <500 ms every leg; the post-latency retry serves CID-verified.
result: pass
evidence: "CI run 42905264387 (user-accepted): suite ran in-lane, 100% per leg"

### 13. Wall-Clock Soak — True kill-9 + Resume, Evidence Trio
expected: The committed evidence trio exists in 12-soak-evidence/ (README with kill procedure, run-capture showing the kill at Critical watermark pending=170 and resume convergence 2162==2162 plus the verification leg PASSED 19975==19975, status-capture with watermark/pending lines) and the zero-match redaction grep holds.
result: pass
evidence: "12-soak-evidence trio verified on disk this session: run-capture kill at Critical/pending=170 + resume convergence 2162==2162 + verification leg; status-capture watermark/pending lines; zero-match redaction grep"

### 14. Tier-1 Registration + Tier-3 Gating of the Wall-Clock Soak
expected: cold_storage_soak_test is registered in the Tier-1 lane (4/4 tests) while cold_storage_wallclock_soak is Tier3/dev-gated with NO Tier1 label; the SGNS_SOAK_ITERATIONS and RESUME env knobs are present in the wall-clock binary.
result: pass
evidence: "CI run 42905264387: cold_storage_soak_test registered and green in-lane; wall-clock soak correctly absent from CI (Tier3/dev-gated, no false failure)"

### 15. SC4 Fresh-Clone Tag-Build Proof (run 42905264387)
expected: 12-FRESH-CLONE-CHECKLIST.md records SuperGenius Tag Build run 42905264387 (head 9994718ce, all fifteen matrix jobs success) with tests + cold storage enabled: Windows Release 153/153, Linux x86_64 Release 152/152, OSX Release 155/155 — the -DSGNS_COLD_STORAGE=ON configure flag and the consumed rtti dependency tag verified in each leg's log (or the run page itself shows all-green with those counts).
result: pass
evidence: "12-FRESH-CLONE-CHECKLIST.md verified on disk this session: run 42905264387, head 9994718ce, tag test_coldstorage_rtti log-verified per leg, 153/153 + 152/152 + 155/155"

### 16. Test Fakes Installed With the Library
expected: The thirdparty sgns-blockstore release tarball installs InMemoryS3Client.hpp / InMemoryS3AdminClient.hpp under include/sgns-blockstore/ — a fresh-clone tarball consumer (as the CI legs proved) compiles the cold-storage test suites with zero source-tree overlay.
result: pass
evidence: "Checklist: install(FILES ...) rule at sgns-blockstore ee0266b + tar payload verification (headers under include/sgns-blockstore/) + CI fresh-clone legs compiled the suites from the install tree alone"

### 17. Tier-Label Audit Green in the CI Lane
expected: The tier1_static_audit test ran and passed inside the tag-build CI lane for the first time — visible in the run 42905264387 log or recorded in the fresh-clone checklist evidence.
result: pass
evidence: "Checklist audit section + Linux leg log: tier1_static_audit Test #15/152 Passed (0.03 s), included in the 100% count"

## Summary

total: 17
passed: 17
issues: 0
pending: 0
skipped: 0

## Gaps

[none yet]
