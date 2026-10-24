---
phase: 08-spill-on-write-background-drainer
plan: 03
subsystem: testing
tags: [cold-storage, drainer, benchmark, hermetic-tests, backpressure, ci-readiness]

requires:
  - phase: 08-spill-on-write-background-drainer
    provides: plans 08-01/08-02 - decorator, manager, config surface, five journal cases
provides:
  - Drainer behavior suite: drain-to-S3, crash-restart reconciliation (pre-loaded remote, exactly-once), s3d-down window (publishes keep succeeding, Warn->Critical->None), enqueue-never-inline, shutdown grace + fresh-manager resume, degenerate inputs
  - SC1 latency-independence benchmark (drainer paused vs running under 300 ms injected remote latency, decorator level)
  - Partial-success backoff evidence (successes advance, cycle fails, heal drains promptly)
  - Honest Phase-8 CI-readiness disposition (ON-lane still blocked-on-thirdparty-release-cut)
affects: [09-cold-read-fallback, 12-integration-hardening, TEST-02 lane]

actuals:
  tokens: 26000
  tasks: 2
  commits: 4

tech-stack:
  added: []
  patterns:
    - bounded-deadline poll loops (never fixed sleeps) for thread-behavior assertions
    - test-local S3Client wrappers (LatencyInjectingS3Client, FlakyS3Client) over the in-repo fake

key-files:
  created: []
  modified:
    - SuperGenius/test/src/crdt/cold_storage_spill_test.cpp
    - SuperGenius/docs/evidence/cold-storage/cold-storage-ci-readiness.md

key-decisions:
  - "SC1 measured at the decorator level (OQ4 resolved): deterministic, no pubsub/graphsync scaffolding; NEVER ON-vs-OFF (Pitfall 8) - paused-vs-running with injected latency"
  - "LatencyInjectingS3Client carries SetPutLatency so the teardown path zeroes the 300 ms injection and Stop() joins in seconds instead of paying 200 x 300 ms"
  - "Crash shape uses scoped store destruction (the library tests' own crash oracle) rather than asserting explicit Close() success - Close returns RocksDB's close status while the lock frees regardless"
  - "Behavior polls require drainer_healthy (false until the first completed cycle) so pending==0 cannot pass vacuously on the initial atomic value"

patterns-established:
  - "Vacuous-poll guard: poll predicates must include a state bit that only real work can set"
  - "Benchmark evidence emission via marked stdout lines ([SC1] ...) - SUCCEED streams do not print"

requirements-completed: [SPILL-01, SPILL-02]

coverage:
  - id: D1
    description: "Drainer behavior suite: drain-to-S3 byte-identical with Accepted-only journal, crash-restart reconciliation with pre-loaded remote (exactly N objects), s3d-down window with watermark Warn->Critical->None and every set() succeeding"
    requirement: SPILL-02
    verification:
      - kind: unit
        ref: "SuperGenius ctest cold_storage_spill_test (13 TESTs total, Passed)"
        status: pass
    human_judgment: false
  - id: D2
    description: "SC1 latency-independence benchmark: paused vs running distributions match ([0.5x, 2.0x] medians) and both p99s stay far below the 300 ms injected latency"
    requirement: SPILL-01
    verification:
      - kind: unit
        ref: "cold_storage_spill_test#sc1_set_latency_independent_of_drainer_state (paused median=1.98ms p99=2.14ms | running median=1.98ms p99=2.25ms, 300ms injected)"
        status: pass
    human_judgment: false
  - id: D3
    description: "Partial-success backoff: 4 of 6 items advance while the cycle counts failed (health false), failed items retained, heal drains promptly with reset"
    requirement: SPILL-02
    verification:
      - kind: unit
        ref: "cold_storage_spill_test#partial_success_cycle_advances_and_backs_off (Passed)"
        status: pass
    human_judgment: false
  - id: D4
    description: "Phase-8 CI-readiness disposition: gated tests named, local ON-lane Tier-1 command + counts recorded, ON-lane still blocked-on-thirdparty-release-cut, no CI yaml change"
    requirement: SPILL-01
    verification:
      - kind: automated
        ref: "ctest -L Tier1 --no-tests=error (100% passed, 3 tests, 2026-10-24) recorded in cold-storage-ci-readiness.md Phase-8 section"
        status: pass
    human_judgment: false

duration: 55min
completed: 2026-10-24
status: complete
---

# Phase 8 Plan 03: Drainer Behavior Suite + SC1 Benchmark Summary

**Hermetic Tier-1 evidence for all five ROADMAP success criteria - drain, crash-resume, outage window, latency independence (1.98 ms medians both ways vs 300 ms injected), and partial-success backoff - plus the honest blocked-on-release-cut CI disposition.**

## Performance

- **Duration:** ~55 min
- **Completed:** 2026-10-24 (UTC)
- **Tasks:** 2
- **Files modified:** 2 (test suite extended 416 -> 715 lines; evidence doc +31 lines)

## Accomplishments
- Six behavior TESTs prove the drainer end-to-end: byte-identical drain to S3 with Accepted-only journal advancement (never Durable - Phase-10 boundary), crash-restart reconciliation converging to exactly N distinct remote objects against a pre-loaded fake, the s3d-down window where every publish succeeds while the watermark climbs Warn->Critical and recovers to None after healing, enqueue-never-inline (RequestDrain returns immediately, the drainer thread drains), shutdown grace + one-resume-path, and degenerate inputs (single block + zero-length block drain)
- SC1 latency-independence: 200 timed decorator sets with the drainer paused vs 200 with it actively draining through a 300 ms-per-Put latency wrapper - medians 1.98 ms vs 1.98 ms, p99 2.14 ms vs 2.25 ms, both distributions matching and both p99s two orders below the injection
- Partial-success (OQ3): 4 of 6 items advance to UploadedAccepted while the cycle counts as a backoff failure (health false), the 2 failed items stay pending and un-lost, and after the wrapper heals the next cycle drains promptly with the backoff reset
- The CI-readiness doc carries the Phase-8 disposition: spill tests are SGNS_COLD_STORAGE-gated (they link the library), the local Windows ON-lane Tier-1 run (3/3, 2026-10-24) stands in, the CI ON-lane stays blocked-on-thirdparty-release-cut with the re-verification command unchanged, and no cmake.yml change was made

## Task Commits

1. **Task 1: drainer behavior suite** - `968ece955` (test, SuperGenius)
2. **Task 2: SC1 benchmark + partial-success + CI disposition** - `09197c688` (test) + `77f4fcf` (docs submodule) + `093e2a866` (docs pointer)

## Files Created/Modified
- `SuperGenius/test/src/crdt/cold_storage_spill_test.cpp` - +8 TESTs (6 behavior + benchmark + partial-success), LatencyInjectingS3Client/FlakyS3Client wrappers, PollUntil + vacuous-poll guard, TimingStats
- `SuperGenius/docs/evidence/cold-storage/cold-storage-ci-readiness.md` - Phase-8 disposition section (nested docs submodule)

## Decisions Made
- Benchmark teardown zeroes the injected latency before Stop() so the join does not pay the full 200 x 300 ms cycle tail
- Crash simulation releases the store via scoped destruction (the library's own crash oracle) instead of asserting explicit Close() success
- All thread-behavior polls require drainer_healthy so the initial atomic values can never satisfy a predicate vacuously

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Plan consistency] Task 1's TEST-count gate off-by-one**
- **Found during:** Task 1 (verify)
- **Issue:** the plan's <verify> requires >= 12 TEST lines but its own behavior block names exactly six new TESTs over the prior five (11); the count materializes only after Task 2's two additions
- **Fix:** implemented the named-test list exactly (11 at Task 1, logging this deviation); final state 13 >= 12 satisfies the phase-level gate
- **Verification:** final grep 13; suite green
- **Committed in:** 968ece955 / 09197c688

**2. [Rule 2 - Test reliability] Vacuous initial-state polls**
- **Found during:** Task 1 (first suite run - 4 failures)
- **Issue:** pending_upload_count starts at 0, so pending==0 polls passed before the first drain cycle ever ran
- **Fix:** poll predicates now also require drainer_healthy (false until the first completed cycle)
- **Verification:** 13/13 green, twice
- **Committed in:** 968ece955

**3. [Rule 2 - Environment] SuperGenius/docs is a nested submodule**
- **Found during:** Task 2 (commit)
- **Issue:** the evidence doc path rejected by the SuperGenius index - docs/ is its own submodule
- **Fix:** commit innermost first (docs 77f4fcf) then bump SuperGenius's pointer (093e2a866)
- **Verification:** git status clean at both levels
- **Committed in:** 77f4fcf + 093e2a866

**Total deviations:** 3 auto-fixed (1 plan-consistency, 1 test-reliability, 1 environment)
**Impact on plan:** None - final gates all green; the count-gate discrepancy was plan-internal.

## Issues Encountered
None beyond the deviations above.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Phase 8 evidence complete: all five ROADMAP success criteria have committed Tier-1 proof on the ON tree
- The seam decorator's get()/contains() still pure-forward - Phase 9 (cold read fallback) extends exactly there
- CI ON-lane remains blocked on the thirdparty release cut (follow-up recorded in the readiness doc)

---
*Phase: 08-spill-on-write-background-drainer*
*Completed: 2026-10-24*
