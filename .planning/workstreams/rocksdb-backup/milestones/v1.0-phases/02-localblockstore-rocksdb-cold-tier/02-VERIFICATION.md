---
phase: 02-localblockstore-rocksdb-cold-tier
status: passed
verified_at: 2026-10-20
verifier: inline (Copilot runtime — gsd-verifier contract)
goal: >-
  Blocks persist durably on local disk through LocalBlockStore's own RocksDB
  instance — atomic writes and a crash-recoverable upload journal establish the
  LocalCommitted tier and the crash-safety machinery the S3 tier reuses
requirements: [BACK-03, BACK-04]
must_haves_verified: 4
must_haves_total: 4
human_verification: []
gaps: []
---

# Phase 02 Verification — LocalBlockStore (RocksDB Cold Tier)

Goal-backward verification: does the codebase deliver what the phase promised (not merely completed tasks)? All evidence below is from the real superbuild tree (`thirdparty/build/Windows/Debug/sgns-blockstore/src/sgns-blockstore-build`), gathered during this execution run.

## Success Criteria

### SC 1 — Restart durability through the store's OWN RocksDB instance ✅

**Claim:** a block Put survives process restart, retrieved byte-identical and CID-verified; own instance/directory (consumer-provided), never the GlobalDB handle; API-compatible with RocksDB 9.4 and 11.1.

**Evidence:**
- `RestartDurabilityPreservesBlocksAndJournal` (local_block_store_test, PASSED in the phase-seal run): Put cid_a+cid_b → no-flush close → reopen → both blocks byte-identical, CID-verified (Get's verify-on-read path), pending set == exactly the two CIDs.
- Own instance: `LocalBlockStore::Open` constructs its own `rocksdb::DBOptions` + CF descriptors and opens the consumer-provided directory; repo-wide grep shows zero GlobalDB/CRDT references in `thirdparty/sgns-blockstore` (`git grep -i globaldb` over the repo returns nothing).
- Dual-compat by construction: `find_package(RocksDB CONFIG REQUIRED)` with NO version argument anywhere (negative grep gate green — SameMajorVersion config cannot reject an 11.1.2 consumer), and pimpl keeps every RocksDB symbol out of installed headers (negative grep over `include/` green).

### SC 2 — Phase-1 conformance kit green against LocalBlockStore ✅

**Evidence:** `SGNS_BLOCKSTORE_CONFORMANCE_TESTS(LocalBlockStoreConformance, MakeFreshLocalStore)` registers 18 kit case entries (xunit check green); `local_block_store_test` PASSED in the phase-seal run (kit + 11 behavior tests). The kit's fault cases (Unavailable/CorruptData/non-sticky/Unauthorized) exercise the FaultController seam and pass — including after the D-09 self-heal branch landed (regression gate).

### SC 3 — Interrupted write never leaves a torn block ✅

**Evidence:** the complete D-08 pair, green in `local_block_store_crash_test` (PASSED):
- `CrashBeforeCommitLeavesNothing`: seam-armed Put fails TemporarilyUnavailable before any `DB::Write`; after no-flush close + reopen, Get is NotFound, Has false, pending set EMPTY.
- `CrashAfterCommitRecoversBlockAndPending`: committed Put + no-flush close + reopen recovers the CID-verified block AND its journal record together.
- There is no mid-`DB::Write` observable state (one WriteBatch = one atomic WAL record; kPointInTimeRecovery) — the pair is complete by construction and documented in the seam's Doxygen and the crash-test file header.

### SC 4 — Restart reconciles the durable upload journal; temp-sweep vacuous ✅

**Evidence:**
- `JournalTransitionsReconcileAcrossRestart` (crash suite): MarkUploadedDurable before close survives reopen; pending set == exactly the still-pending CID; both blocks retrievable.
- `JournalStateSurvivesRestart` (02-02 suite): same shape for Accepted-state persistence.
- `VacuousSweepDocumentationHolds`: behavioral pin across two restart cycles — pending set is always exactly the committed set, no artifacts.
- Header documents the D-02 mapping verbatim: `LocalBlockStore.hpp` class Doxygen states BACK-03's "(temp + fsync + rename)" = one WriteBatch + `WriteOptions::sync=true` through RocksDB's WAL machinery, and ROADMAP Phase-2 criterion 4's "sweeps stale temp files" is VACUOUS by design — startup sweep IS journal reconciliation only.

## Requirements Traceability

| ID | Requirement | Status | Evidence |
|----|-------------|--------|----------|
| BACK-03 | Own RocksDB instance (never GlobalDB), atomic writes, 9.4/11.1 API-compatible | [x] Complete in REQUIREMENTS.md | SC 1 + SC 3 evidence; one-atomic-batch Put proven (02-01 acceptance gates: exactly one `db_->Write` in the Put path, `wo_.sync=true` set once at open) |
| BACK-04 | Durable upload journal, recoverable after crash | [x] Complete in REQUIREMENTS.md | SC 4 evidence; journal born in the same batch as the block (RestartDurability..., CrashAfterCommit...), explicit transitions + conservative decode (02-02 suite green) |

## Cross-Checks

- Frozen-contract integrity: `BlockStore.hpp` unchanged since Phase 1; `BlockStoreTooling.hpp` changed only by the sanctioned additive D-05 method (diff vs 02-01 state empty for both after 02-01's landing).
- Phase-seal full-tree ctest: 6/6 binaries green (memory kit + cid spike + local suite/kit + crash suite + api hygiene + header hygiene) — prior-phase suites included, no cross-phase regressions.
- Prohibition gates: no Flush/SyncWAL calls under `test/` (call-form grep green); no rocksdb includes under `include/`; no versioned RocksDB find.
- Review gate: REVIEW.md 0 Critical / 1 Warning / 3 Info — advisory, 0-block (disposition recorded).

## Verdict

**PASSED — 4/4 success criteria verified against the codebase; both requirements accounted for and marked complete. No human-verification items; no gaps.**
