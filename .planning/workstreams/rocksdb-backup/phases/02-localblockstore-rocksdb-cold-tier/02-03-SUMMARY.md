---
phase: 02-localblockstore-rocksdb-cold-tier
plan: 03
subsystem: database
tags: [crash-safety, wal-replay, corruption-self-heal, crash-seam, reconciliation]

# Dependency graph
requires:
  - phase: 02-localblockstore-rocksdb-cold-tier
    provides: journal state machine (transitions + accessor), EvictLocal, kit instantiation, durable slice
provides:
  - CrashPoint seam (BeforeCommit) + SetCrashPointForTesting - additive, test-only, FaultController untouched
  - D-09 evict-and-surface self-heal in Get (fault-path gated: fault_ != CorruptData)
  - SC 3 proof pair: crash-before-commit leaves NOTHING; crash-after-commit recovers block + journal together
  - SC 4 proof: journal transitions reconcile exactly across restart; vacuous temp-sweep documented in-header (D-02 / criterion 4)
affects: [05-fault-injection-three-tier-hardening, 04-s3blockstore-sia-s3d-roundtrip]

actuals:
  tokens: 8000
  tasks: 2
  commits: 3

tech-stack:
  added: []
  patterns: [in-process crash-window pair (seam + no-flush close + reopen), raw second RocksDB handle as the only real-corruption forge]

key-files:
  created:
    - thirdparty/sgns-blockstore/test/local_block_store_crash_test.cpp
  modified:
    - thirdparty/sgns-blockstore/include/sgns-blockstore/LocalBlockStore.hpp
    - thirdparty/sgns-blockstore/src/LocalBlockStore.cpp
    - thirdparty/sgns-blockstore/test/CMakeLists.txt

key-decisions:
  - "Eviction branch gated on fault_ != FaultKind::CorruptData - fault-induced copy corruption never evicts (Pitfall 3); kit non-sticky cases stay green by regression"
  - "No mid-DB::Write fault point exists or is needed: a WriteBatch is ONE atomic WAL record - before/after is the complete D-08 pair"
  - "Self-heal eviction write is best-effort: failure appended to the Corrupt message, never swallowed, Corrupt still returned"

patterns-established:
  - "Crash test = seam-arm -> failing Put / committing Put -> no-flush close -> reopen -> assert WAL-replay invariants (never Flush/SyncWAL)"
  - "Raw-handle corruption forge: second rocksdb::DB (create_if_missing=false), flip stored value byte, full teardown order - test-binary-only RocksDB link"

requirements-completed: [BACK-03, BACK-04]

coverage:
  - id: D1
    description: "D-09 self-heal: real on-disk corruption evicts-and-surfaces with journal co-removal and re-Put repair; fault-induced corruption never evicts"
    requirement: BACK-03
    verification:
      - kind: unit
        ref: "test/local_block_store_crash_test.cpp#StoredCorruptionSelfHealsEvictAndSurface / #FaultCorruptionDoesNotEvict"
        status: pass
      - kind: command
        ref: "local_block_store_test (kit FaultCorruptData/non-sticky cases) still green after the branch landed"
        status: pass
    human_judgment: false
  - id: D2
    description: "SC 3 crash-window pair: before-commit leaves nothing (NotFound + empty journal), after-commit recovers block + pending together"
    requirement: BACK-03
    verification:
      - kind: unit
        ref: "test/local_block_store_crash_test.cpp#CrashBeforeCommitLeavesNothing / #CrashAfterCommitRecoversBlockAndPending"
        status: pass
    human_judgment: false
  - id: D3
    description: "SC 4 reconciliation: transitions recover exactly across restart; vacuous-sweep mapping stated in header and behaviorally pinned"
    requirement: BACK-04
    verification:
      - kind: unit
        ref: "test/local_block_store_crash_test.cpp#JournalTransitionsReconcileAcrossRestart / #VacuousSweepDocumentationHolds"
        status: pass
      - kind: command
        ref: "phase-seal full inner-tree ctest 6/6 binaries green; no Flush/SyncWAL calls under test/; install tree carries rebuilt lib + header"
        status: pass
    human_judgment: false
---

# Phase 02 Plan 03: Crash-Safety Proofs Summary

**One-liner:** The crash-window pair is proven (before-commit leaves nothing, after-commit recovers block+journal together via WAL replay), real on-disk corruption self-heals evict-and-surface (fault-path gated), and journal transitions reconcile exactly across restart — full tree 6/6 green.

Duration: ~25 min | Tasks: 2 | Files: 4 | Commits: sgns-blockstore `44d7d9e` (RED) + `1162a5d` (GREEN) + `1500223` (reconciliation)

## Accomplishments

- **CrashPoint seam (Task 1, TDD RED→GREEN):** additive `enum class CrashPoint { None, BeforeCommit }` + `SetCrashPointForTesting` on the concrete type only (frozen FaultController untouched); BeforeCommit short-circuits Put AFTER gates/verification/presence-probe and BEFORE any `db_->Write` — caller never sees success, nothing is written.
- **D-09 self-heal:** Get's CID-verification failure now splits the two corruption sources — fault-induced (returned-copy flip) surfaces Corrupt+Local with NO eviction; genuine stored-bytes failure commits ONE removal WriteBatch{blocks Delete, journal Delete} (best-effort, failure appended to message) then surfaces Corrupt+Local. `StoredCorruptionSelfHealsEvictAndSurface` forges REAL corruption via a raw second RocksDB handle (create_if_missing=false, published CF constants, flip stored byte, full teardown) and proves: Corrupt once → NotFound → Has false → journal co-removed → re-Put repairs alreadyPresent=false. `FaultCorruptionDoesNotEvict` pins the gate.
- **Reconciliation suite (Task 2):** `CrashAfterCommitRecoversBlockAndPending` (block + journal ride ONE WAL record — recover together or not at all), `JournalTransitionsReconcileAcrossRestart` (UploadedDurable survives, pending set == exactly the still-pending CID), `VacuousSweepDocumentationHolds` (behavioral pin of the D-02 mapping; header now names ROADMAP criterion 4's "sweeps stale temp files" as vacuous by design).
- **Phase seal:** full inner-tree ctest 6/6 binaries green (memory kit + spike + behavior/kit + crash + hygiene + header_hygiene); no Flush/SyncWAL calls under test/ (grep gate green — one match was the prohibition's own doc comment, re-run with call-form patterns passes); install tree carries the rebuilt `sgns-blockstore.lib` and installed `LocalBlockStore.hpp`.

## Task Execution Table

| Task | Name | Result | Commit |
|------|------|--------|--------|
| 1 | D-09 self-heal + BeforeCommit seam (TDD) | Done - RED 44d7d9e → GREEN 1162a5d, kit regression green | 44d7d9e/1162a5d |
| 2 | Reconciliation suite + phase seal | Done - 6/6 binaries, install tree OK | 1500223 |

## Deviations from Plan

**[Rule 1 - tooling] Prohibition grep false positive** — Found during: Task 1 gates. The plan's grep pattern `->Flush\(|SyncWAL` matched the crash-test file's own documentation comment stating the prohibition. Fix: re-ran with call-form-only patterns (`->Flush(`, `->SyncWAL(`, `.Flush(`, `.SyncWAL(`) — zero matches. No code change. Verification: gate PASS.

**Total deviations:** 1 (tooling only). **Impact:** none on code.

## Issues Encountered

None.

## Next Phase Readiness

Phase 2 proof obligations complete. Phase 3 (minio-cpp integration, --research-phase flagged) builds on an untouched frozen contract; Phase 5's subprocess-kill matrix and WAL-tail mangling extend the crash model additively.
