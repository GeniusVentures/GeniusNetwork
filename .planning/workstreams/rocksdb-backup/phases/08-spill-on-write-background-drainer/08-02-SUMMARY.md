---
phase: 08-spill-on-write-background-drainer
plan: 02
subsystem: database
tags: [cold-storage, drainer, backpressure, config, thread-lifecycle, watermarks]

requires:
  - phase: 08-spill-on-write-background-drainer
    provides: plan 08-01 - gated stack, decorator, shared cold_store_mutex, ON-configured tree
provides:
  - blockstore.backpressure strict config surface (drain_interval_ms/warn_pending/critical_pending/backoff_cap_ms, 0-defaults, loud validation)
  - ColdStorageManager drainer thread (split-phase DrainOnce, exponential backoff, dual count watermarks, atomics status, bounded-grace stop, first-poll crash reconciliation)
  - GlobalDB lifecycle wiring (Start beside StartBackupLoop, Stop immediately after StopBackupLoop, GetColdStorageStatus active-accessor)
  - ColdStorageStack factory fills bundle.manager with normalized options; four bridges real
  - Wallet asset schema parity (blank backpressure sub-object)
affects: [08-03, 11-retention-gc, GeniusSDK status surfacing]

actuals:
  tokens: 30000
  tasks: 2
  commits: 3

tech-stack:
  added: []
  patterns:
    - backup-loop lifecycle transplanted to a second service (thread + cv + grace-then-join)
    - split-phase drain (locked snapshot/fetch/mark, unlocked remote Put)

key-files:
  created:
    - SuperGenius/src/crdt/globaldb/ColdStorageManager.hpp
    - SuperGenius/src/crdt/globaldb/ColdStorageManager.cpp
  modified:
    - SuperGenius/src/crdt/globaldb/globaldb.hpp
    - SuperGenius/src/crdt/globaldb/globaldb.cpp
    - SuperGenius/src/crdt/globaldb/ColdStorageStack.cpp
    - SuperGenius/src/crdt/globaldb/CMakeLists.txt
    - SuperGenius/test/src/crdt/cold_storage_config_gate_test.cpp
    - GeniusWallet/assets/crdt_config.json

key-decisions:
  - "DrainOnce composes the Phase-2 library surfaces directly (snapshot/fetch under the shared mutex, remote Put unlocked, mark under the mutex again) instead of one lock-scoped DrainPendingUploads call - the free function interleaves remote Puts between journal ops and a single lock scope would hold the publisher mutex across S3 latency (D-01)"
  - "GlobalDB reaches the manager through private no-arg member bridges (StartColdStorageManager/StopColdStorageManager) that delegate to the free stack bridges - globaldb.cpp stays free of library types and the call-form anchors the shutdown ordering gate"
  - "Factory defensively re-normalizes still-0 backpressure knobs (programmatic ColdStorageOptions bypass the parser) and enforces warn<critical loudly at stack-open time"

patterns-established:
  - "Backpressure config: nested strict sub-object, 0=per-knob built-in default, pair validation post-normalization"
  - "Status atomics + active-accessor getter: no journal scan, no lock on the read path"

requirements-completed: [SPILL-02]

coverage:
  - id: D1
    description: "blockstore.backpressure strict parser (absent/blank/0 defaults; non-object/unknown-key/wrong-type/warn>=critical loud failures) + LogSummary fields + wallet asset parity"
    requirement: SPILL-02
    verification:
      - kind: unit
        ref: "SuperGenius ctest cold_storage_config_gate_test (26 TESTs, 100% passed)"
        status: pass
      - kind: automated
        ref: "grep gates: 5 blockstore.backpressure message refs in globaldb.cpp; wallet asset backpressure present; credential-log gate 0 matches"
        status: pass
    human_judgment: false
  - id: D2
    description: "ColdStorageManager drainer thread (cv poll loop, split-phase DrainOnce, backoff with cap+reset, watermark transitions + heartbeat, grace-then-join Stop, RequestDrain enqueue) wired into GlobalDB lifecycle with ordered joins"
    requirement: SPILL-02
    verification:
      - kind: integration
        ref: "cmake --build crdt_globaldb genius_node exit 0; ctest crdt_test + globaldb_integration_test 100% passed"
        status: pass
      - kind: automated
        ref: "structural gates: GetPendingUploads x3, RequestDrain x1, Warn x2, no detach, line-order StopBackupLoop(398) < StopColdStorageManager(402)"
        status: pass
    human_judgment: false
  - id: D3
    description: "Behavioral drainer evidence (drain-to-S3, crash-resume, s3d-down window, enqueue-never-inline, shutdown grace, benchmark) - deferred to plan 08-03 by the ROADMAP wave design"
    requirement: SPILL-02
    verification: []
    human_judgment: true
    rationale: "Behavioral suites land in 08-03 (wave 3) per the phase plan; this plan's letter is structural wiring + config surface, both machine-verified above."

duration: 65min
completed: 2026-10-24
status: complete
---

# Phase 8 Plan 02: Backpressure Config + Background Drainer Summary

**Strict blockstore.backpressure config surface plus the SuperGenius-owned ColdStorageManager drainer - a backup-loop-pattern thread with split-phase drain, exponential backoff, always-on dual watermarks, and bounded-grace shutdown wired into GlobalDB's lifecycle.**

## Performance

- **Duration:** ~65 min
- **Completed:** 2026-10-24 (UTC)
- **Tasks:** 2
- **Files modified:** 8 (2 created, 6 modified) + 1 wallet asset

## Accomplishments
- The Phase-7 strict parser grew the nested blockstore.backpressure sub-object with 0-defaults semantics, loud unknown-key/wrong-type/non-object/warn>=critical failures naming the offender, and post-normalization pair validation; the matrix grew from 17 to 26 green cases
- ColdStorageManager: cv-based poll loop (first poll = D-12 crash-restart reconciliation), split-phase DrainOnce that never holds the shared cold-store mutex across remote S3 I/O, exponential backoff (factor 2, cap, reset on first success, partial-success counts as failed cycle per OQ3), dual record-count watermarks with always-on transition + heartbeat logging, atomics-backed D-08 status getter, bounded-grace stop with unconditional join
- GlobalDB lifecycle: drainer starts beside StartBackupLoop in Start(), stops immediately after StopBackupLoop in ShutdownNow() (line-order gate 398<402) and before the lifecycle_mutex_ teardown; GetColdStorageStatus rides the active-accessor pattern
- The factory fills bundle.manager with defensively normalized options and the four bridges are real; existing CRDT suites stay green

## Task Commits

1. **Task 1: strict backpressure config + matrix + wallet parity** - `a587326cc` (feat, SuperGenius) + `44d378cd` (feat, GeniusWallet)
2. **Task 2: ColdStorageManager drainer + lifecycle wiring** - `b0e5498a9` (feat)

## Files Created/Modified
- `SuperGenius/src/crdt/globaldb/ColdStorageManager.hpp/.cpp` - the drainer service (thread, backoff, watermarks, status, grace stop)
- `SuperGenius/src/crdt/globaldb/globaldb.hpp` - BackpressureOptions nested struct, GetColdStorageStatus, no-arg lifecycle bridge members, forward-declared status types
- `SuperGenius/src/crdt/globaldb/globaldb.cpp` - parser extension + normalization + pair validation, LogSummary fields, ShutdownNow/Start wiring, bridge member definitions
- `SuperGenius/src/crdt/globaldb/ColdStorageStack.cpp` - manager construction with normalized options, real null-safe bridges, shared (not moved) store handles
- `SuperGenius/src/crdt/globaldb/CMakeLists.txt` - ColdStorageManager.cpp joins the gated source list
- `SuperGenius/test/src/crdt/cold_storage_config_gate_test.cpp` - nine new backpressure cases (26 total)
- `GeniusWallet/assets/crdt_config.json` - blank backpressure sub-object (schema parity; wallet never activates)

## Decisions Made
- Split-phase drain composed from the frozen Phase-2 surfaces rather than a lock-scoped DrainPendingUploads call (UploadDrainer.hpp's composition note blesses this exact shape; a single lock scope would violate D-01's never-blocked-writes letter)
- GlobalDB member wrappers (no-arg) delegate to the free bridges, keeping library types out of globaldb.cpp and satisfying the call-form shutdown-ordering gate
- Backpressure knobs are file-only (no env surface), inheriting Phase 7's credentials-only env rule

## Deviations from Plan

None - plan executed exactly as written (the fixture composition bug in the new matrix cases was fixed inside the task before commit; all gates green).

## Issues Encountered
One routine compile fix (plain bool used with .load() in the Stop grace predicate) - corrected within the task commit.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- ColdStorageManager is directly constructible in hermetic tests (D-10) with injected BackpressureOptions - 08-03's behavior suite drives it over the real LocalBlockStore + InMemoryS3Client fake
- All surfaces 08-03 asserts exist: Start/Stop/RequestDrain/GetStatus, watermark transitions, crash-resume via a fresh manager over the same directory

---
*Phase: 08-spill-on-write-background-drainer*
*Completed: 2026-10-24*
