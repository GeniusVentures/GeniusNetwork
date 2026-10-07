---
phase: 06-price-claim-wire-format-history
plan: 01
subsystem: testing
tags: [cpp, boost-asio, strand, price-history, coinprices, supergenius]

# Dependency graph
requires:
  - phase: 03-price-manager
    provides: LocalPriceManager strand architecture (ioc/strand/runner thread, injectable Clock, FakePriceSource test seam)
  - phase: 04-price-retrieval-chain
    provides: two-tier fetch walk (DispatchBatchOnStrand) that produces the network-only `fetched` quote set
provides:
  - PriceObservation / PriceHistoryStats / PriceHistoryConfig types on sgns::LocalPriceManager
  - Strand-confined bounded genius-ai price history (retention + count cap, oldest evicted first)
  - Blocking QueryHistory(from,to) post+future bridge returning count/min/max over an inclusive window
  - Documented empty-after-restart semantics (count==0 = no coverage, callers own policy)
affects: [07-price-validation (Phase 7 validator consumes QueryHistory), 06-02 WIRE plan]

actuals:
  tokens: 5812   # chars/4 over the realized submodule diff (23247 chars, 3 files)
  tasks: 2
  commits: 2     # measured: git rev-list --count 60ecfae..HEAD in SuperGenius

tech-stack:
  added: []
  patterns:
    - "History member confinement: new state declared after windows_, before logger/thread_ (destruction-order rule), zero mutexes — strand only"
    - "Query mirror of GetQuotes: same not-on-strand assert + post+future blocking bridge for every new strand-confined read"
    - "Retention prune against injected now_() with linear scan (timestamps non-monotonic across tiers); count-cap eviction from front (insertion order)"

key-files:
  created: []
  modified:
    - SuperGenius/src/coinprices/LocalPriceManager.hpp
    - SuperGenius/src/coinprices/LocalPriceManager.cpp
    - SuperGenius/test/src/price_manager/price_manager_test.cpp

key-decisions:
  - "Record point: RecordObservations called in DispatchBatchOnStrand after the tier walk (fetched final) and before per-waiter assembly — never in HandleRequestOnStrand/StoreInL1, so L1 hits are structurally never recorded (D-06-05)"
  - "Retention prune scans the whole deque (remove_if), not a sorted front — observation timestamps may be non-monotonic across tiers (pitfall 5); the count cap still evicts from the front (insertion order)"
  - "Consecutive identical (timestamp, price) observations are skipped (A2 dedupe) so a tier re-serving one fetchedAt envelope doesn't inflate count"
  - "PriceHistoryConfig as optional trailing ctor param (defaulted) keeps the existing make_shared<LocalPriceManager>(tier1,tier2) call sites source-compatible — verified, no call-site edits"

patterns-established:
  - "Bounded strand-local evidence buffer: append-on-network-success, prune-on-record (retention vs injected clock + count cap), linear-scan inclusive-window query"

requirements-completed: [HIST-01, HIST-02]

coverage:
  - id: D1
    description: "Every genius-ai quote fetched from a network tier is appended to the local history; L1 cache hits are never recorded"
    requirement: HIST-01
    verification:
      - kind: unit
        ref: "SuperGenius/test/src/price_manager/price_manager_test.cpp#LocalPriceManagerTest.HistoryRecordsOneNetworkFetch"
        status: pass
      - kind: unit
        ref: "SuperGenius/test/src/price_manager/price_manager_test.cpp#LocalPriceManagerTest.HistoryL1HitIsNotRecorded"
        status: pass
    human_judgment: false
  - id: D2
    description: "History is bounded: retention prune against the injected clock on next record, count cap evicting the oldest, consecutive-duplicate skip, non-genius-ai assets filtered"
    requirement: HIST-01
    verification:
      - kind: unit
        ref: "SuperGenius/test/src/price_manager/price_manager_test.cpp#LocalPriceManagerTest.HistoryRetentionPrunesOldEntriesOnNextRecord"
        status: pass
      - kind: unit
        ref: "SuperGenius/test/src/price_manager/price_manager_test.cpp#LocalPriceManagerTest.HistoryCountCapEvictsOldest"
        status: pass
      - kind: unit
        ref: "SuperGenius/test/src/price_manager/price_manager_test.cpp#LocalPriceManagerTest.HistorySkipsConsecutiveDuplicateObservations"
        status: pass
      - kind: unit
        ref: "SuperGenius/test/src/price_manager/price_manager_test.cpp#LocalPriceManagerTest.HistoryIgnoresNonGeniusAiAssets"
        status: pass
    human_judgment: false
  - id: D3
    description: "QueryHistory(from,to) returns inclusive-window count/min/max via the strand bridge; empty/no-coverage window returns count==0 without error; empty-after-restart semantics documented in the header (D-06-06/D-06-07)"
    requirement: HIST-02
    verification:
      - kind: unit
        ref: "SuperGenius/test/src/price_manager/price_manager_test.cpp#LocalPriceManagerTest.HistoryWindowBoundsAreInclusive"
        status: pass
      - kind: unit
        ref: "SuperGenius/test/src/price_manager/price_manager_test.cpp#LocalPriceManagerTest.HistoryEmptyOnFreshManagerReturnsZeroCount"
        status: pass
      - kind: unit
        ref: "SuperGenius/test/src/price_manager/price_manager_test.cpp#LocalPriceManagerTest.HistoryQueryHandlesNonMonotonicTimestamps"
        status: pass
    human_judgment: false

duration: 15min
completed: 2026-10-05
status: complete
---

# Phase 6 Plan 1: Local Price History Summary

**Bounded, timestamped, strand-confined genius-ai price history in LocalPriceManager with inclusive-window min/max/count queries and documented empty-after-restart degradation — no mutexes, no call-site churn.**

## Performance

- **Duration:** ~15 min
- **Started:** 2026-10-06T01:04:15Z
- **Completed:** 2026-10-06T01:19Z (UTC)
- **Tasks:** 2/2
- **Files modified:** 3 (all in SuperGenius submodule, branch dev_price_validation)

## Accomplishments

- Network-fetched genius-ai quotes are recorded once per tier walk (D-06-05): `RecordObservations` is called in `DispatchBatchOnStrand` after the walk completes and before per-waiter assembly; the L1-hit path structurally cannot record.
- History is bounded two ways (T-06-01): retention prune against the injected clock (default 24h) and a count cap (default 4096) evicting oldest first; consecutive identical (timestamp, price) observations are deduped (A2).
- `QueryHistory(from,to)` mirrors `GetQuotes` exactly — same not-on-strand assert, same post+future blocking bridge — returning `{count,min,max}` over an inclusive window via linear scan (non-monotonic-safe); count==0 means "no coverage", never an error (HIST-02).
- Header documents the restart and role semantics: in-memory only, empty after restart, Phase-7 callers own the no-coverage policy, local evidence — not a validity ruling (D-06-06/D-06-07).

## Task Commits

Each task was committed atomically (submodule `SuperGenius`, branch `dev_price_validation`):

1. **Task 1: Tracer — record one network fetch and query it back through the strand** - `8a374c4f8` (feat)
2. **Task 2: Expand — retention, count cap, window bounds, filtering, empty/restart behaviour** - `26a40a1b6` (feat)

**Plan ledger:** `plan_head_before: 60ecfae9af68909460bcba5e6d97aecea6684651` → `plan_head_after: 26a40a1b6` (2 commits, measured)

## Files Created/Modified

- `SuperGenius/src/coinprices/LocalPriceManager.hpp` — PriceObservation/PriceHistoryStats/PriceHistoryConfig types, optional trailing PriceHistoryConfig ctor param, QueryHistory declaration, historyConfig_/history_ members (after windows_, before logger/thread_), class-comment documentation of restart/role semantics
- `SuperGenius/src/coinprices/LocalPriceManager.cpp` — ctor historyConfig wiring, RecordObservations (asset filter + A2 dedupe + retention prune + cap eviction), QueryHistory strand bridge, RecordObservations call site in DispatchBatchOnStrand
- `SuperGenius/test/src/price_manager/price_manager_test.cpp` — 9 hermetic `*History*` tests (FakePriceSource + injected clock, zero network), MakeManager extended with optional PriceHistoryConfig

## Verification

- TDD per task: RED first (Task 1: compile-fail on absent API; Task 2: 3 failing tests — retention, cap, dedupe), then GREEN.
- `price_manager_test.exe --gtest_filter=*History*`: 9/9 pass.
- Full `price_manager_test.exe`: pass.
- `ctest --test-dir SuperGenius\build\Windows\Release -C Release -R "price_"`: 5/5 pass (price_quote, price_http_client, price_facade, price_manager, price_retrieval).
- Existing ctor call sites unchanged: only production call site is `GeniusNode.cpp:3545` `make_shared<LocalPriceManager>(tier1, tier2)` — source-compatible via the defaulted param (test binary compiles the identical fully-defaulted path). No other call sites exist in src/ or test/.

## Decisions Made

- Retention prune is a full-deque `remove_if` (timestamps may be non-monotonic across tiers); only the cap evicts from the front. Documented inline.
- Hard-coded `"genius-ai"` record filter (research open question 2 resolved per D-06-05 recommendation).
- No JSON/config wiring for history knobs (plan-granted discretion; config keys unnecessary this phase).

## Deviations from Plan

None - plan executed exactly as written.

**Out-of-scope discoveries (not fixed, logged to [deferred-items.md](./deferred-items.md)):**
1. `LocalPriceManagerTest.ConcurrentGetQuotesAcrossThreadsAllResolve` is a pre-existing timing flake on this loaded Windows host (~2 failures in 8 full-suite runs; 0 in 9 isolated runs; failure = one thread's GetQuotes returning false). Unrelated to this diff — that test uses non-genius-ai ids, which `RecordObservations` filters out before any history work.
2. The `genius_node` target has a pre-existing compile error (`GeniusNode.cpp:2307`, `C2039 '__this'`, UPnP block) untouched by this plan (submodule diff is exactly the 3 planned files; file last modified by merge `f44199411` before the plan base). Ctor-call-site compatibility for this plan is proven by the compiling/running price_manager_test, which exercises the fully-defaulted parameter chain.

**Impact on plan:** none — both items predate the plan and lie outside its 3-file scope.

## Issues Encountered

- Initial full-binary run showed the concurrency-test flake above; classified with a 14-run reproduction matrix before proceeding (no fix — scope boundary).

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Phase 7 (validator) can call `QueryHistory(from, to)` from any non-strand thread; it owns the no-coverage policy when `count==0` and the tolerance/window defaults (D-06-03).
- Plan 06-02 (WIRE) proceeds independently: proto field, GetProcessCost struct, GeniusNode/SDK plumbing — none of which this plan touched.
- Known blocker for 06-02 executor: `genius_node` target currently fails to compile on this host (pre-existing `__this` error) — see deferred-items.md; price_* targets are unaffected.

---
*Phase: 06-price-claim-wire-format-history (workstream: tokenprice)*
*Completed: 2026-10-05*

## Self-Check: PASSED

All 3 modified source files exist; both task commits (`8a374c4f8`, `26a40a1b6`) verified on `dev_price_validation` via `git log`; 06-01-SUMMARY.md exists at the expected path.
