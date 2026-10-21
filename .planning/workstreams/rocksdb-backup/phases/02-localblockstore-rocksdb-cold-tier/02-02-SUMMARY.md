---
phase: 02-localblockstore-rocksdb-cold-tier
plan: 02
subsystem: database
tags: [rocksdb, upload-journal, state-machine, eviction, conformance-kit]

# Dependency graph
requires:
  - phase: 02-localblockstore-rocksdb-cold-tier
    provides: LocalBlockStore durable slice (one-batch Put+journal, GetPendingUploads, fault seam, build wiring)
provides:
  - Journal state machine: MarkUploadedAccepted / MarkUploadedDurable / GetUploadState on the concrete type only (D-06)
  - Unconditional idempotent EvictLocal removing block bytes + journal record in one sync WriteBatch (D-10)
  - Re-Put no-regression proof (Pitfall 6) and no-fabrication transition semantics (T-02-08)
  - Phase-1 conformance kit instantiation running green against LocalBlockStore (SC 2)
affects: [04-s3blockstore-sia-s3d-roundtrip, 05-fault-injection-three-tier-hardening]

actuals:
  tokens: 9000
  tasks: 2
  commits: 3

tech-stack:
  added: []
  patterns: [read-journal-first transitions (no fabricated records), unconditional one-batch eviction, per-case fresh-dir kit factory]

key-files:
  created: []
  modified:
    - thirdparty/sgns-blockstore/include/sgns-blockstore/LocalBlockStore.hpp
    - thirdparty/sgns-blockstore/src/LocalBlockStore.cpp
    - thirdparty/sgns-blockstore/test/local_block_store_test.cpp
    - thirdparty/sgns-blockstore/test/api_hygiene_test.cpp

key-decisions:
  - "Transitions move Put-born records only: read-journal-first, NotFound-without-write on unknown CIDs (T-02-08 mitigation)"
  - "Kit macro takes a callable, not a call result - SGNS_BLOCKSTORE_CONFORMANCE_TESTS(Suite, MakeFreshLocalStore)"
  - "EvictLocal deletes absent keys successfully - idempotence falls out of the unconditional one-batch delete"

patterns-established:
  - "Journal transition = gate -> MakeKey -> read journal -> ONE WriteBatch{journal Put} -> sync write; shared TransitionJournal helper"
  - "Per-case kit factory: atomic counter + remove_all + short relative kit-case-N dir; ADD_FAILURE+nullptr on Open failure"

requirements-completed: [BACK-03, BACK-04]

coverage:
  - id: D1
    description: "Journal state machine: explicit transitions, state reader, restart persistence, re-Put no-regression, entry gates"
    requirement: BACK-04
    verification:
      - kind: unit
        ref: "test/local_block_store_test.cpp#JournalBirthStateIsPendingUpload / #MarkUploadedAcceptedMovesStateAndShrinksPending / #MarkUploadedDurableMovesStateBlockRetrievable / #JournalStateSurvivesRestart / #TransitionOnUnknownCidIsNotFound / #RePutDoesNotRegressJournalState / #TransitionsRespectEntryGates"
        status: pass
    human_judgment: false
  - id: D2
    description: "EvictLocal: unconditional one-batch removal of block+journal, idempotent, journal-state-ignoring, re-Put repairs"
    requirement: BACK-03
    verification:
      - kind: unit
        ref: "test/local_block_store_test.cpp#EvictLocalRemovesBlockAndJournalRecord / #EvictLocalIsIdempotent / #EvictLocalIgnoresJournalState / #RePutAfterEvictRepairs"
        status: pass
    human_judgment: false
  - id: D3
    description: "Phase-1 conformance kit green against LocalBlockStore (fault cases included) + D-16 guard covers both backends"
    requirement: BACK-03
    verification:
      - kind: unit
        ref: "SGNS_BLOCKSTORE_CONFORMANCE_TESTS(LocalBlockStoreConformance, MakeFreshLocalStore) - 18 kit case entries in xunit"
        status: pass
      - kind: command
        ref: "full inner-tree ctest 5/5 binaries pass; frozen headers diff-empty vs 02-01"
        status: pass
    human_judgment: false
---

# Phase 02 Plan 02: Journal Lifecycle + Conformance Kit Summary

**One-liner:** The upload journal became a durable, explicitly-transitioned, restart-recoverable state machine (Mark→Read→Recover), EvictLocal delivers D-10's unconditional one-batch local removal, and the Phase-1 conformance kit runs green against LocalBlockStore.

Duration: ~25 min | Tasks: 2 | Files: 4 | Commits: sgns-blockstore `dad0a48` (RED) + `31ffe35` (GREEN) + `f482f29` (kit+evict)

## Accomplishments

- **Journal state machine (Task 1, TDD RED→GREEN):** `MarkUploadedAccepted`/`MarkUploadedDurable` transition an existing record in ONE sync WriteBatch via a shared `TransitionJournal` helper (gates → MakeKey → read-journal-first → one journal-CF Put); unknown CIDs return NotFound WITHOUT writing (no fabricated upload state, T-02-08); `GetUploadState` reports absence as NotFound, never a default value, with conservative PendingUpload fallback for undecodable records. Seven behavior tests green including `JournalStateSurvivesRestart` (UploadedDurable survives no-flush close + WAL replay; pending set reconciles to exactly the still-pending CID) and `RePutDoesNotRegressJournalState` (Pitfall 6).
- **EvictLocal (Task 2):** unconditional ONE sync WriteBatch{blocks Delete, journal Delete}; journal state never consulted (D-10); idempotent by construction; D-10 data-loss-when-pending caveat documented in the header Doxygen. Four behavior tests green (co-removal, idempotence, ignores-journal-state, re-Put repairs with alreadyPresent=false and re-born PendingUpload).
- **SC 2 delivered:** `SGNS_BLOCKSTORE_CONFORMANCE_TESTS(LocalBlockStoreConformance, MakeFreshLocalStore)` — per-case fresh unique dir (atomic counter + remove_all + short path), ADD_FAILURE+nullptr on Open failure; 18 kit case entries in xunit; full inner-tree ctest 5/5 binaries green (kit + behavior + memory regression + spike + hygiene + header_hygiene).
- **D-16 guard extended:** `static_assert(HasEvictLocal<LocalBlockStore>::value)` beside the MemoryBlockStore assert; api_hygiene still compiles standalone with zero RocksDB on its link line.

## Task Execution Table

| Task | Name | Result | Commit |
|------|------|--------|--------|
| 1 | Journal transitions + state reader + restart persistence (TDD) | Done - RED dad0a48 → GREEN 31ffe35, 7/7 green | dad0a48/31ffe35 |
| 2 | EvictLocal + kit instantiation + placement guard | Done - 4/4 eviction tests, 18 kit cases, 5/5 binaries | f482f29 |

## Deviations from Plan

**[Rule 1 - API usage] Kit macro factory argument** — Found during: Task 2 build (C2064). The macro expands `store_ = FACTORY()`; passing `MakeFreshLocalStore()` (a call result) yields `MakeFreshLocalStore()()`. Fix: pass the callable `MakeFreshLocalStore`. Files: test/local_block_store_test.cpp. Verification: kit compiled + 18 cases green. Commit: f482f29.

**Total deviations:** 1 auto-fixed. **Impact:** none.

## Issues Encountered

None.

## Next Phase Readiness

Plan 02-03 adds the crash-safety proofs (crash-before/after-commit pair via an additive in-process crash seam, D-09 evict-and-surface self-heal on real on-disk corruption, journal-transition reconciliation across restart) — all on the proven architecture, no interface change.
