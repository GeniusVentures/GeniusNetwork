---
phase: 10-flush-gated-durability-advancement
plan: 02
subsystem: infra
tags: [s3d, fault-injection, staging-health, durability, cold-storage, testing]

requires:
  - phase: 10-flush-gated-durability-advancement plan 01
    provides: the advancement construction (cadence step, evidence gate, batched marks, final flush), the InMemoryS3AdminClient scripting surface, flush_backoff plumbing
provides:
  - SC3 honesty evidence: crash-between-journal-and-drain reconciliation over mixed Pending+Accepted leftovers, admin-outage never-NotFound with drain/flush backoff independence, GarbageStats conservative failure, bounded Stop() under SlowFlush load with the resume path
  - Discharge of both 10-01 flagged assumptions by wired tests (idempotent replay over all-Durable; mid-flush acceptance race excluded from the cycle's marks)
  - SC4 staging health: raw s3d counters + conservative staging_healthy (D-12 three-clause predicate, kStagingBufferFraction 0.8 public) in ColdStorageStatus, evaluated on every stats-observing tick
  - RefreshStagingStats() on-demand entry (D-13) serialized via admin_mutex_ - no poller thread
  - Restart count seeding (first-cycle GetUploadsInState scans) - accepted/durable counts survive restart while GetStatus stays a pure atomics read
  - Sustained-flush-failure alarm family ("cold-storage flush ..." wording, first-failure detail + rate-limited repeats + recovery) and flush_backoff_active status field
affects: [11-retention-gc-of-cold-eligible-crdt-data]

actuals:
  tokens: 13000
  tasks: 2
  commits: 7

tech-stack:
  added: []
  patterns:
    - "fault-injection honesty suite: every fault shape scripted through the same fake surface production consumes"
    - "on-tick + on-demand freshness: predicate evaluates where the observation already happens; a dedicated admin mutex is the only serialization"

key-files:
  created: []
  modified:
    - SuperGenius/src/crdt/globaldb/ColdStorageManager.hpp
    - SuperGenius/src/crdt/globaldb/ColdStorageManager.cpp
    - SuperGenius/src/crdt/globaldb/ColdStorageStack.hpp
    - SuperGenius/test/src/crdt/cold_storage_durability_test.cpp
    - thirdparty/sgns-blockstore/src/InMemoryS3AdminClient.cpp
    - thirdparty/sgns-blockstore/test/s3_admin_client_test.cpp

key-decisions:
  - "Empty-snapshot cadence fix (10-02 construction change per the flagged-assumption protocol): AdvanceDurabilityOnce no longer skips the cycle when the Accepted snapshot is empty - the flush + stats observation still runs on the cadence (staging freshness + idempotent replay both require it; marks are naturally empty)"
  - "Budget-faithful fake: InMemoryS3AdminClient::Flush honors the per-call read budget (a scripted delay beyond it surfaces the client-side timeout after the budget elapses) - the bounded-Stop proof works through the fake, and the wire-level timeout remains proven against the real client by the black-hole test"
  - "flush_backoff_active as an atomic status mirror rather than exposing the drainer-only streak; staging counters keep last-known values on unreadable evidence (fail-safe direction)"
  - "Black-hole listener is event-driven (future released at Stop): the Tier-1 static audit bans fixed-sleep constructs in test sources - loopback literals are audit-neutralized, sleeps are not"

patterns-established:
  - "Honesty tests discharge flagged assumptions: construction-level flags from a prior plan get wired fault tests in the proof plan; if a test falsifies the construction, the construction is fixed - never the test"

requirements-completed: [DUR-01]

coverage:
  - id: D1
    description: "Crash-between-journal-and-drain reconciliation: mixed Pending+Accepted leftovers recover through first-poll re-drain + first-cycle advancement"
    requirement: DUR-01
    verification:
      - kind: unit
        ref: "SuperGenius/test/src/crdt/cold_storage_durability_test.cpp#crash_reconciliation_mixed_leftovers"
        status: pass
  - id: D2
    description: "Admin outage (Unreachable): decorator publishes keep succeeding, states never surface NotFound, drain health holds while flush backoff engages independently and resets on recovery"
    requirement: DUR-01
    verification:
      - kind: unit
        ref: "SuperGenius/test/src/crdt/cold_storage_durability_test.cpp#admin_outage_never_not_found_and_drain_unpoisoned"
        status: pass
  - id: D3
    description: "GarbageStats conservative failure (zero marks, valid=false) with recovery; sustained-flush alarm in the distinguishable 'cold-storage flush' family"
    requirement: DUR-01
    verification:
      - kind: unit
        ref: "SuperGenius/test/src/crdt/cold_storage_durability_test.cpp#garbage_stats_keeps_accepted_then_recovers"
        status: pass
  - id: D4
    description: "Shutdown under load with SlowFlush: Stop() bounded by grace + final budget + margin, records left Accepted, fresh manager resumes"
    requirement: DUR-01
    verification:
      - kind: unit
        ref: "SuperGenius/test/src/crdt/cold_storage_durability_test.cpp#shutdown_under_load_slow_flush_bounded"
        status: pass
  - id: D5
    description: "Idempotent replay (10-01 flag discharge): extra cycles over all-Durable advance flush_count while marking nothing"
    requirement: DUR-01
    verification:
      - kind: unit
        ref: "SuperGenius/test/src/crdt/cold_storage_durability_test.cpp#idempotent_replay_marks_nothing"
        status: pass
  - id: D6
    description: "Acceptance race (10-01 flag discharge): a CID accepted mid-flush via the on_flush hook does not ride the cycle's evidence; exactly the next cycle advances it"
    requirement: DUR-01
    verification:
      - kind: unit
        ref: "SuperGenius/test/src/crdt/cold_storage_durability_test.cpp#acceptance_race_mid_flush_excluded_from_marks"
        status: pass
  - id: D7
    description: "SC4 staging predicate: healthy/fraction-exceeded/zero-limit-unlimited/failed-growth/fail-safe-on-unreachable, all through the status getter with raw counters"
    requirement: DUR-01
    verification:
      - kind: unit
        ref: "SuperGenius/test/src/crdt/cold_storage_durability_test.cpp#staging_healthy_on_clean_stats + 4 sibling staging cases"
        status: pass
  - id: D8
    description: "D-13 on-demand refresh (test-thread call against a running drainer) and restart count seeding from pre-existing journal records"
    requirement: DUR-01
    verification:
      - kind: unit
        ref: "SuperGenius/test/src/crdt/cold_storage_durability_test.cpp#staging_refresh_on_demand_updates_without_tick / staging_restart_seeding_counts"
        status: pass
  - id: D9
    description: "Tier-1 close-out: SuperGenius -L Tier1 6/6, library -L Tier1 14/14 (incl. tier1_static_audit), parity 6==6, GetStatus purity source assertion clean"
    requirement: DUR-01
    verification:
      - kind: integration
        ref: "ctest -L Tier1 lanes in both trees + PowerShell gates (all pass)"
        status: pass

duration: 45min
completed: 2026-10-26
status: complete
---

# Phase 10 Plan 02: Flush-Gated Durability — Honesty Evidence Summary

**The 10-01 advancement construction is now proven honest under fault — crash reconciliation, admin outages, bounded shutdown, idempotent replay, and the acceptance race all hold — and Phase 11's GC inhibitor has its staging-health signal: raw s3d counters plus a conservative healthy predicate, fresh on every tick and on demand.**

## Performance

- **Duration:** 45 min
- **Tasks:** 2/2 | **Commits:** 7 (4 SuperGenius, 2 sgns-blockstore + 1 thirdparty pointer... 3 pointer/fake commits total)
- **File count:** 6 modified (no new files - the suite extends the existing ctest target)

## Accomplishments

1. **SC3 fault suite (6 scenarios):** crash reconciliation over mixed leftovers (stranded Accepted records advance at the first eligible tick after the first-poll re-drain); admin Unreachable with decorator publishes unbroken, never-NotFound state reads, drainer_healthy true while flush_backoff_active engages independently; GarbageStats conservative zero-mark failure with recovery; bounded Stop() under a publishing thread with SlowFlush beyond kFinalFlushBudgetMs (records left Accepted, resume proven); idempotent replay (flush_count advances, nothing marked); mid-flush acceptance race (the late CID waits for the next cycle).
2. **Both 10-01 flagged assumptions discharged** by wired tests, per the flagged-assumption protocol — one construction change resulted: the empty-snapshot early-return was removed (the cadence observation must keep running; staging freshness and idempotent replay both depend on it).
3. **Sustained-flush-failure alarm:** first-failure line carries the BlockStatus context and engaged backoff delay, repeats rate-limited every 10th, recovery logged; "cold-storage flush ..." wording stays distinguishable from the drainer family; drainer_healthy is never falsified by flush failures (Pitfall 6).
4. **SC4 staging health:** the D-12 three-clause predicate (buffer fraction with vacuous-true zero-limit, flat failedUploads delta, admin reachable) evaluates on every stats-observing tick; five raw counter fields + staging_healthy live in ColdStorageStatus; RefreshStagingStats() is the D-13 on-demand entry serialized through admin_mutex_; restart seeding re-derives accepted/durable counts at thread start so the counts survive restart while GetStatus stays a pure atomics read.
5. **Fake-contract fixes:** the admin fake honors per-call read budgets (slow-flush-beyond-budget surfaces the timeout), and the wire test's black-hole listener is event-driven (future-released hold) — both keeping the library's Tier-1 static audit green.

## Issues Encountered

tier1_static_audit initially failed on the wire test's fixed-sleep black hole — restructured to an event-driven hold before the GREEN commit (see Deviations).

## Deviations from Plan

- **[Rule 1 - Construction fix per flagged-assumption protocol] Empty-snapshot cadence change** — Found during: Task 1 (idempotent-replay test). Issue: 10-01's "empty snapshot => idle-record and return" made an all-Durable journal stop observing entirely, contradicting D-03 replay semantics (flush_count must still advance) and starving Task 2's on-tick staging freshness. Fix: AdvanceDurabilityOnce proceeds to flush+observe on the cadence regardless of snapshot emptiness (marks are naturally empty - the batched mark over an empty span is a no-op). Verification: idempotent_replay_marks_nothing + all staging tests green. Commit: 56caba1de.
- **[Rule 1 - Test-infrastructure] Budget-faithful SlowFlush fake** — Found during: Task 1 (shutdown-under-load test). Issue: the fake slept the full scripted delay regardless of the caller's read budget, so a delay > kFinalFlushBudgetMs could not surface the timeout the real client produces - the bounded-Stop proof was impossible through the fake. Fix: delay beyond the budget sleeps the budget then returns the timeout-shaped TemporarilyUnavailable (InMemoryS3AdminClient.cpp - one file outside this plan's files_modified). Verification: shutdown_under_load_slow_flush_bounded green; wire-level timeout still proven against the REAL client (FlushReadBudgetBoundsABlockedResponse). Commits: 0c1d07b + 451b4dd.
- **[Rule 1 - Audit compliance] Event-driven black-hole listener** — Found during: Task 2 close-out (tier1_static_audit). Issue: the wire test's `sleep_for(3s)` hold violated the Tier-1 fixed-sleep ban. Fix: future-released hold, no timed sleeps. Verification: library -L Tier1 14/14. Commit: 451b4dd.

**Total deviations:** 3 auto-fixed (1 sanctioned construction fix, 2 test-infrastructure). **Impact:** none on plan semantics - every must_have and prohibition holds; the one construction change is exactly the protocol the plan's flagged-assumption block prescribes.

## Authentication Gates

None.

## Self-Check: PASSED

- All 2 tasks executed; RED then GREEN commits per tdd task
- cold_storage_durability_test: 21 cases green (8 from 10-01 + 6 SC3 + 7 SC4... 13 new); sibling spill/fallback suites green; config gate green
- SuperGenius -L Tier1 6/6; library -L Tier1 14/14 (audit + parity included); GetStatus purity clean; registration parity 6==6

## Next Phase Readiness

Phase 10 complete at the plan level: SC1-SC4 all evidenced. DUR-01 is now fully dischargable (both declaring plans summarized). Phase 11 (Retention GC) can consume kEvictionDurabilityGate, GetColdUploadState, and staging_healthy as its inhibition contract.
