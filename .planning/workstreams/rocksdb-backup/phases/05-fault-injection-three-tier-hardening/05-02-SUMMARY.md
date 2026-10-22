---
phase: 05-fault-injection-three-tier-hardening
plan: 02
subsystem: database
tags: [rocksdb, wal-recovery, crash-testing, fault-injection, c++]

requires:
  - phase: 05-fault-injection-three-tier-hardening
    provides: the labeled Tier1 lane and the tier1_static_audit tripwire (plan 05-01)
provides:
  - LocalBlockStore::SetCorruptAfterCommitForTesting TEST-ONLY seam (the D-09 corrupt-after-commit hook) on the backend type
  - Crash suite fully API-only (second RocksDB handle, rocksdb includes, and the RocksDB::rocksdb test link retired)
  - The complete four-state crash matrix: states 3 (uploaded-but-unmarked, idempotent re-drain convergence) and 4 (accepted, no-op re-drain) plus the D-02 window-model banner
affects: [05-03, phase verification]

actuals:
  tokens: 4200
  tasks: 2
  commits: 3

tech-stack:
  added: []
  patterns:
    - "Backend-seam corruption hook: commit-tail in-place corruption through the store's own handles (sync write-back) so stored-corruption proofs stay API-only"

key-files:
  created: []
  modified:
    - thirdparty/sgns-blockstore/include/sgns-blockstore/LocalBlockStore.hpp
    - thirdparty/sgns-blockstore/src/LocalBlockStore.cpp
    - thirdparty/sgns-blockstore/test/local_block_store_crash_test.cpp
    - thirdparty/sgns-blockstore/test/CMakeLists.txt

key-decisions:
  - "The hook reuses impl_->wo_ (the production sync WriteOptions) for the corruption write-back - satisfies D-09's sync requirement without constructing options at the seam"
  - "State 3 constructed via direct remote Put without the drainer mark (the drain-then-close ordering RESEARCH endorsed) - no new fault seam needed in this plan"

patterns-established:
  - "Four-state window model documentation lives in the crash-suite banner next to the tests that prove each state (D-02's documentation home)"

requirements-completed: [TEST-02]

coverage:
  - id: D1
    description: "D-09 corrupt-after-commit hook on LocalBlockStore (TEST-ONLY, CrashPoint-precedent shape) with the crash suite re-pointed to it and the second RocksDB handle fully retired"
    requirement: TEST-02
    verification:
      - kind: unit
        ref: "local_block_store_crash_test: 100% passed - StoredCorruptionSelfHealsEvictAndSurface re-pointed (assertions unchanged), FaultCorruptionDoesNotEvict untouched"
        status: pass
      - kind: other
        ref: "token gates: SetCorruptAfterCommitForTesting + corrupt_after_commit_ in hpp+cpp; FaultController.hpp contains no CorruptAfterCommit (frozen); git grep zero CorruptStoredBlock/RocksDB::rocksdb/rocksdb-include residue"
        status: pass
    human_judgment: false
  - id: D2
    description: "Four-state crash matrix completed: state-3 uploaded-but-unmarked reconciles via idempotent re-drain (alreadyPresent==true, journal advances to UploadedAccepted) and state-4 accepted is stable with no-op re-drain; D-02 window model documented in the banner"
    requirement: TEST-02
    verification:
      - kind: unit
        ref: "per-case runs: [OK] CrashAfterRemoteUploadBeforeMarkReconcilesViaReDrain (130ms), [OK] AcceptedStateIsStableAndReDrainIsNoOp (117ms); full -L Tier1 lane 12/12 (adjacent suites unregressed)"
        status: pass
    human_judgment: false

duration: 35min
completed: 2026-10-22
status: complete
---

# Phase 5 Plan 02: Crash-Safety Proofs Summary

**All four journal-lifecycle crash windows are now proven through in-process reopen + WAL recovery + journal reconciliation, with stored corruption forged API-only through the new D-09 backend seam.**

## Performance

- **Duration:** ~35 min (2 tasks)
- **Tokens (actuals):** ~4.2K over 4 changed files

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| 1 | 26fe7f4 (sgns-blockstore) | D-09 corrupt-after-commit hook + API-only crash suite (link retirement) |
| 2 | fbcad8a (sgns-blockstore) | four-state crash matrix completion - states 3 and 4 (D-01..D-04) |
| ptr | 467c913 (thirdparty) | sgns-blockstore pointer bump |

## What Was Built

- **Hook (D-09):** `SetCorruptAfterCommitForTesting(bool)` + `corrupt_after_commit_` on LocalBlockStore (FaultController.hpp untouched - token-gated). Fires in the Put commit tail between the `committed.ok()` gate and the PutOutcome return: reads the just-committed value back through `impl_->blocks_`, XORs 0xFF into the first byte, writes it back through `impl_->db_` on the sync WriteOptions. Never touches the journal CF, never fires on already_present re-Put, never routed through fault_/FaultGate.
- **API-only crash suite:** CorruptStoredBlock (raw second RocksDB handle + kBlocksColumnFamilyName coupling), both rocksdb includes, and the `RocksDB::rocksdb` link + its justification comment are deleted; StoredCorruptionSelfHealsEvictAndSurface arms the hook before Put with every assertion unchanged; the src/ include privilege (in_memory_s3_client_test precedent) lands for the states-3/4 fake reach.
- **Matrix (D-02/D-03/D-04):** state 3 - uploaded-but-unmarked window (direct remote Put, no drainer mark), reopen surfaces PendingUpload + pending {cid}, re-drain converges with alreadyPresent==true and advances to UploadedAccepted, both tiers CID-verified; state 4 - accepted stable across recovery and the second drain is a no-op (empty result vector). Banner carries the four-state window model incl. the mid-write-does-not-exist atomicity rationale.

## Verification Evidence

- Crash suite 100%: both new cases individually OK (130ms/117ms), both corruption regressions green, full `-L Tier1` lane 12/12 (adjacent suites compile clean against the modified header).
- Seam gates: hook symbols present (hpp+cpp), frozen FaultController clean, zero second-handle residue by git grep, arming pair present, zero Flush/SyncWAL calls (call-form gate).

## Deviations from Plan

**[Rule 1 - Plan-internal gate wording] No-flush token gate tripped on the banner itself** — Found during: Task 1 verification | Issue: the plan's verify regex `SyncWAL|->Flush\(` matches the preserved banner sentence "No test calls Flush() or SyncWAL() anywhere" (a documented tree landmine - the banner states the prohibition) | Fix: ran the call-form gate (`->SyncWAL(|.SyncWAL(|->Flush(|.Flush(`) matching the acceptance criterion's intent ("no Flush()/SyncWAL() CALL anywhere") - zero call matches; no code change needed | Files: none | Verification: call-form grep clean; suite green | Commit: n/a (gate interpretation only)

**Total deviations:** 1 auto-fixed (gate wording). **Impact:** none - all D-01..D-04/D-09 truths hold as written.

## Self-Check: PASSED

- All tasks executed and committed individually
- SUMMARY created in the plan directory
- Acceptance criteria re-verified green (crash battery 100%, seam/token/git-grep gates, no-flush call-form gate, adjacent suites + full Tier1 lane unregressed)
