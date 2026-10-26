---
phase: 09-cold-read-fallback-local-reads-graphsync-serving
plan: 02
subsystem: database
tags: [cold-storage, blockstore, graphsync, responder, re-warm, executor, sc2]

requires:
  - phase: 09-cold-read-fallback-local-reads-graphsync-serving (plan 01)
    provides: ColdReadFallback hook, ColdReadService chain (Get/Rehydrate/HasLocalCold), remote_store_mutex_, taxonomy Error values
provides:
  - ColdReadService re-warm executor: single dedicated worker thread, bounded queue (64), per-CID coalescing map, Start/Stop lifecycle, kRewarmBudget/kMaxRewarmQueueDepth/kRewarmShutdownGraceWindow compile-time defaults
  - ColdServeDagService responder wrapper (delegate-or-enqueue, never block) wired into StartSync's graphsync_->start
  - StartColdReadService/StopColdReadService bridges (real + ODR stub twins) + GlobalDB lifecycle slot (ShutdownNow, after the drainer, before lifecycle-mutex teardown)
  - cold_read_freeze_latency_test (SC2 benchmark + freeze regression, Tier-1, evidence banner with measured distributions)
affects: [11-retention-gc, 12-integration-hardening, 10-flush-gated-durability]

actuals:
  tokens: 24000
  tasks: 3
  commits: 3

tech-stack:
  added: []
  patterns:
    - Bounded-queue try-enqueue executor with per-CID dedup map (no futures/waiters - nobody waits, RESEARCH §8.2)
    - Responder wrapper delegation discipline (never wait/sleep/lock-across-I/O on the single-thread pubsub io_context)

key-files:
  created:
    - SuperGenius/test/src/crdt/cold_read_freeze_latency_test.cpp
  modified:
    - SuperGenius/src/crdt/globaldb/ColdReadService.hpp
    - SuperGenius/src/crdt/globaldb/ColdReadService.cpp
    - SuperGenius/src/crdt/graphsync_dagsyncer.hpp
    - SuperGenius/src/crdt/impl/graphsync_dagsyncer.cpp
    - SuperGenius/src/crdt/globaldb/ColdStorageStack.hpp
    - SuperGenius/src/crdt/globaldb/ColdStorageStack.cpp
    - SuperGenius/src/crdt/globaldb/ColdStorageStackStub.cpp
    - SuperGenius/src/crdt/globaldb/globaldb.hpp
    - SuperGenius/src/crdt/globaldb/globaldb.cpp
    - SuperGenius/src/crdt/globaldb/BlockStoreBackedIpfsDatastore.cpp
    - SuperGenius/test/src/crdt/cold_storage_fallback_test.cpp
    - SuperGenius/test/src/crdt/CMakeLists.txt

key-decisions:
  - "Re-warm worker starts at construction time inside GlobalDB::New's enabled block (beside the service construction) so every serve miss finds the executor live; Stop slots into ShutdownNow after the drainer per RESEARCH §6.5"
  - "The D-12 constants are public static constexpr on ColdReadService - they ARE the documented built-in defaults the SC2 evidence banner cites"
  - "Chain-failure rate-limiter state gained its own mutex: Get() now runs on both the CRDT DAG worker and the re-warm worker"
  - "ColdServeDagService holds a non-owning ColdReadFallback*; the DAGSyncer member ordering (hook declared before wrapper) keeps it valid"

patterns-established:
  - "Try-enqueue executor: bounded deque + map<CID,RewarmState> under one mutex never held across I/O; overflow/expiry drop + count + rate-limited warn"
  - "Evidence-banner-as-document: the test file's header IS SC2's measured latency-budget record"

requirements-completed: [READ-02]

coverage:
  - id: D1
    description: "Re-warm executor: per-CID coalescing (exactly one chain fetch under duplicate enqueues), bounded non-blocking queue, budget-skipped stale entries, own-thread lifecycle with idempotent bounded-grace Stop (D-07, D-10/D-11)"
    requirement: READ-02
    verification:
      - kind: unit
        ref: "SuperGenius/test/src/crdt/cold_storage_fallback_test.cpp#RewarmCoalescesDuplicateEnqueues"
        status: pass
      - kind: unit
        ref: "SuperGenius/test/src/crdt/cold_storage_fallback_test.cpp#RewarmQueueOverflowDropsWithoutBlocking"
        status: pass
      - kind: unit
        ref: "SuperGenius/test/src/crdt/cold_storage_fallback_test.cpp#RewarmExpiredBudgetEntryIsSkipped"
        status: pass
      - kind: unit
        ref: "SuperGenius/test/src/crdt/cold_storage_fallback_test.cpp#RewarmStopJoinsAndIsIdempotent"
        status: pass
    human_judgment: false
  - id: D2
    description: "Responder cold-serve in the locked D-05 shape: wrapper delegates hot reads, enqueues one coalesced re-warm on miss, returns the failure immediately - never blocks (D-05/D-06, SC2)"
    requirement: READ-02
    verification:
      - kind: unit
        ref: "SuperGenius/test/src/crdt/cold_read_freeze_latency_test.cpp#HotServeNeverWaitsOnSaturatedRewarmQueue"
        status: pass
      - kind: unit
        ref: "SuperGenius/test/src/crdt/cold_read_freeze_latency_test.cpp#UnavailableFaultMissReturnsImmediately"
        status: pass
      - kind: integration
        ref: "ctest -R 'crdt_test|globaldb_integration_test' (green after StartSync wrapper wiring)"
        status: pass
    human_judgment: false
  - id: D3
    description: "SC2 measurements: time-to-warm inside the 4 s budget at 500 ms injected latency; inline chain latency distributions recorded (10/50/200/500 ms); concurrent-miss duplicate-Get count recorded - all in the evidence banner (D-12)"
    requirement: READ-02
    verification:
      - kind: unit
        ref: "SuperGenius/test/src/crdt/cold_read_freeze_latency_test.cpp#TimeToWarmWithinBudgetAt500MsLatency"
        status: pass
      - kind: unit
        ref: "SuperGenius/test/src/crdt/cold_read_freeze_latency_test.cpp#InlineChainLatencyByInjectedGetLatency"
        status: pass
      - kind: unit
        ref: "SuperGenius/test/src/crdt/cold_read_freeze_latency_test.cpp#ConcurrentColdReadsDuplicateGetCount"
        status: pass
    human_judgment: false

duration: 55min
completed: 2026-10-26
status: complete
---

# Phase 9 Plan 02: Graphsync Async Cold-Serve Summary

**Peer requests for cold CIDs now answer an honest immediate don't-have while a bounded, coalesced background re-warm fetches the block hot - the responder never waits, so the whole-node-freeze hazard stays closed.**

## Performance

- **Duration:** 55 min
- **Started:** 2026-10-26T22:50Z (approx)
- **Completed:** 2026-10-26T23:45Z (approx)
- **Tasks:** 3/3
- **Files modified:** 13 (1 created, 12 modified)

## Accomplishments
- Re-warm executor in ColdReadService: single dedicated worker (never io_/pubsub context), 64-deep bounded queue with non-blocking drop+count overflow, per-CID coalescing (proven: exactly one S3 Get under duplicate enqueues), 4 s budget skipping stale entries, Phase-8-shaped Start/Stop with 5 s grace
- ColdServeDagService wrapper handed to graphsync_->start: hot reads delegate, cold misses try-enqueue and return the inner failure unchanged (RS_NOT_FOUND now); null hook = pure delegation (byte-identical disabled bar)
- Lifecycle: StartColdReadService at GlobalDB::New's enabled block; StopColdReadService in ShutdownNow between the drainer stop and the lifecycle-mutex teardown
- SC2 evidence (hermetic, Tier-1): time-to-warm < 4 s at 500 ms injected Get latency; hot-hit serve through the wrapper < 50 ms with 16 queued re-warms and the worker pinned; outage miss path fail-fast; inline chain p50/p95 recorded per latency level (10/50/200/500 ms); concurrent-read duplicate-Get count = 4 recorded for Phase-12

## Task Commits

Each task was committed atomically (SuperGenius submodule, branch dev_blockstore):

1. **Task 1: re-warm executor + bridges + shutdown slot + coalescing/lifecycle tests** - `8ffae19ec` (feat)
2. **Task 2: ColdServeDagService wrapper + StartSync wiring + decorator marker rationale** - `459308fba` (feat)
3. **Task 3: SC2 latency-budget benchmark + freeze regression** - `c730e5be8` (test)

**Plan metadata:** (docs commit follows)

## Files Created/Modified
- `SuperGenius/src/crdt/globaldb/ColdReadService.hpp/.cpp` - executor additions (RewarmState map, bounded queue, worker loop, Start/Stop, public D-12 constants, log-rate mutex)
- `SuperGenius/src/crdt/graphsync_dagsyncer.hpp` / `impl/graphsync_dagsyncer.cpp` - ColdServeDagService declaration/definition, cold_serve_wrapper_ member, StartSync wiring
- `SuperGenius/src/crdt/globaldb/ColdStorageStack.hpp/.cpp` + `ColdStorageStackStub.cpp` - Start/StopColdReadService bridges (ODR twins)
- `SuperGenius/src/crdt/globaldb/globaldb.hpp/.cpp` - lifecycle methods, New enabled-block Start, ShutdownNow slot
- `SuperGenius/src/crdt/globaldb/BlockStoreBackedIpfsDatastore.cpp` - get() marker comment → permanent chain-location rationale
- `SuperGenius/test/src/crdt/cold_storage_fallback_test.cpp` - coalescing/overflow/budget/lifecycle cases + GetLatencyS3Client
- `SuperGenius/test/src/crdt/cold_read_freeze_latency_test.cpp` (new) - SC2 suite with instrumented client, fake inner dag service, evidence banner

## Decisions Made
- Worker Start at construction (New) rather than GlobalDB::Start: a serve miss before Start would drop re-warms silently
- D-12 constants made public on ColdReadService - they are the documented defaults the evidence banner cites (tests reference them)
- The wrapper's hook is a non-owning pointer; DAGSyncer member order (hook before wrapper) guarantees lifetime

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Access fix] D-12 constants moved to the public section**
- **Found during:** Task 1 (build)
- **Issue:** Tests and the evidence banner reference kRewarmBudget/kMaxRewarmQueueDepth; they were initially private
- **Fix:** Moved to the public section with their derivation comments (they are documentation-grade defaults)
- **Files modified:** SuperGenius/src/crdt/globaldb/ColdReadService.hpp
- **Verification:** build green; acceptance grep >= 1
- **Commit hash:** 8ffae19ec

**2. [Rule 1 - API naming] IpldNodeImpl -> IPLDNodeImpl, getCid -> getCID**
- **Found during:** Task 3 (build)
- **Issue:** The fake inner dag service used guessed ipfs-lite names
- **Fix:** Matched the vendored header (IPLDNodeImpl::createFromString, getCID())
- **Files modified:** SuperGenius/test/src/crdt/cold_read_freeze_latency_test.cpp
- **Verification:** suite green
- **Commit hash:** c730e5be8

**Total deviations:** 2 auto-fixed (compile-level). **Impact:** none.

## Issues Encountered

None.

## Next Plan Readiness

Ready for 09-03 - the fault-injection honesty suite builds directly on the hook seam, the landed invariants, and this plan's executor/wrapper surfaces.
