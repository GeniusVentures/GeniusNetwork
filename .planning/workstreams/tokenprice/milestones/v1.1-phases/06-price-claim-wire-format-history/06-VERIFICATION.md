---
phase: 06-price-claim-wire-format-history
verified: 2026-10-06T02:05:00Z
status: passed
score: 9/9 must-haves verified
covered_files:
  - .planning/workstreams/tokenprice/phases/06-price-claim-wire-format-history/06-01-PLAN.md
  - .planning/workstreams/tokenprice/phases/06-price-claim-wire-format-history/06-01-SUMMARY.md
  - .planning/workstreams/tokenprice/phases/06-price-claim-wire-format-history/06-02-PLAN.md
  - .planning/workstreams/tokenprice/phases/06-price-claim-wire-format-history/06-02-SUMMARY.md
  - SuperGenius/src/coinprices/LocalPriceManager.hpp
  - SuperGenius/src/coinprices/LocalPriceManager.cpp
  - SuperGenius/src/processing/proto/SGProcessing.proto
  - SuperGenius/src/account/GeniusNode.hpp
  - SuperGenius/src/account/GeniusNode.cpp
  - SuperGenius/test/src/price_manager/price_manager_test.cpp
  - SuperGenius/test/src/account/account_management_test.cpp
  - SuperGenius/test/src/processing_nodes/processing_nodes_test.cpp
  - SuperGenius/test/src/processing_nodes/child_tokens_test.cpp
  - GeniusSDK/src/GeniusSDK.cpp
covered_digest: "v2:sha256:3d0228f85636d7f3f60bfe730fe02ba210d8d85ea4f13aba7b0b2d64163db8de"
behavior_unverified: 0
overrides_applied: 0
---

# Phase 6: Price Claim Wire Format & History — Verification Report

**Phase Goal:** Every posted job carries a verifiable price claim and every node can answer "what prices did I observe around time T?"
**Verified:** 2026-10-06T02:05:00Z
**Status:** passed
**Re-verification:** No — initial verification (no prior `*-VERIFICATION.md` in the phase dir)

## Goal Achievement

### Observable Truths

Merged must-haves: ROADMAP Phase 6 success criteria + `06-01-PLAN.md` / `06-02-PLAN.md` frontmatter. Roadmap SC1–SC3 map to truths 1/2, 3, 5/6/7 below; no scope was subtracted.

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | `SGProcessing::Task` has `double claimed_price = 6`; old messages parse with `claimed_price()==0.0`, new round-trip exactly (WIRE-01, SC1) | ✓ VERIFIED | `SGProcessing.proto:23` (`double claimed_price = 6;`); tests `TaskClaimedPriceWire.RoundTripPreservesDouble` (account_management_test.cpp:686, EXPECT_DOUBLE_EQ on copied literal) and `TaskClaimedPriceWire.OldMessageParsesAsZero` (:707, fields 1–5 only → 0.0, legacy fields intact) — both ran **PASS** |
| 2 | No timestamp field added to Task (D-06-02) | ✓ VERIFIED | `SGProcessing.proto:7-24`: Task message carries fields 1–6 only; comment at :21-22 documents escrow DAG timestamp as the reference time, not a wire field |
| 3 | `ProcessImage` stamps `claimed_price` from the same quote that sized the escrow — one `GetQuotes` read, no second fetch (WIRE-02, SC2) | ✓ VERIFIED | GeniusNode.cpp:2694 `auto cost = GetProcessCost( *procmgr )` → :2697 `cost.minions <= 0` → :2720 `task.set_claimed_price( cost.quote.price )`; GetProcessCost (:2816-2848) built from ONE `GetGNUSQuote()` (:2828) + `CalculateCostMinions(blockLen, quote.price)`; behavioral test `AccountManagement.ClaimedPriceMatchesEscrowQuote` (test:607) scripts P1→P2 sequencing and asserts claim==P1, escrow==`CalculateCostMinions(4860000,P1)`, later cost==P2-minions ≠ escrow — ran **PASS** (5261 ms) |
| 4 | `GetGNUSPrice`/`GetCoinprice` keep double / map APIs; finite-and-positive genius-ai validation preserved | ✓ VERIFIED | GeniusNode.hpp:405/411/861 signatures unchanged; GetGNUSQuote (cpp:2850-2872) keeps `std::isfinite && price > 0.0` → `Error::NO_PRICE`; GetGNUSPrice (cpp:2873-2881) thin wrapper returning `quote.price`; GetCoinprice (cpp:3581) still returns the map via its own GetQuotes |
| 5 | Every network-tier genius-ai quote is appended to history; L1 cache hits never recorded (D-06-05, HIST-01) | ✓ VERIFIED | `RecordObservations(fetched)` called only from `DispatchBatchOnStrand` (LocalPriceManager.cpp:278, after tier walk / before per-waiter assembly); filter `quote.asset != "genius-ai"` skip at :414-417; tests `HistoryRecordsOneNetworkFetch` (test:873) and `HistoryL1HitIsNotRecorded` (test:892, asserts tier1 CallCount==0 AND count stays 1) — ran **PASS** |
| 6 | `QueryHistory(from,to)` returns count/min/max; empty or no-coverage window returns count==0 without error (HIST-02, SC3) | ✓ VERIFIED | LocalPriceManager.cpp:100-130: post+future bridge, linear scan, `[from,to]` inclusive; tests `HistoryWindowBoundsAreInclusive` (incl. disjoint-window count==0) and `HistoryEmptyOnFreshManagerReturnsZeroCount` — ran **PASS** |
| 7 | History bounded by retention (default 24h, pruned against injected `now_()`) and count cap (default 4096), oldest evicted first (SC3) | ✓ VERIFIED | `PriceHistoryConfig{retention 24h, maxEntries 4096}` (hpp:73-78); prune against `now_() - retention` via remove_if over every entry + `pop_front` cap loop (cpp:437-447); tests `HistoryRetentionPrunesOldEntriesOnNextRecord`, `HistoryCountCapEvictsOldest`, `HistoryQueryHandlesNonMonotonicTimestamps`, `HistorySkipsConsecutiveDuplicateObservations` — all ran **PASS** |
| 8 | History is strand-confined (no mutex); existing ctor call sites `make_shared<LocalPriceManager>(tier1,tier2)` still compile | ✓ VERIFIED | Zero `mutex|lock_guard|unique_lock` matches in LocalPriceManager.hpp/.cpp (only the header comment asserting their absence); `QueryHistory` carries the same `assert(!strand_.running_in_this_thread())` (cpp:105); trailing defaulted `PriceHistoryConfig` ctor param (hpp:88-93); call site GeniusNode.cpp:3576 `make_shared<LocalPriceManager>( tier1, tier2 )` compiles — proven by genius_node_test-linked test binaries building and running on this host |
| 9 | GeniusSDK public API unchanged; every `GetProcessCost` caller migrated to `.minions` | ✓ VERIFIED | Commit `9f2e955` (GeniusSDK): 2-line diff, only `.minions` unwrap at GeniusSDK.cpp:707/:728, no signature/header/FFI change; repo-wide grep over GeniusSDK/GeniusWallet/SuperGenius: all code callers end in `.minions` (tests 464/671, 373/383/526, 597) or are the definition/ProcessImage itself; only non-code hits are prose docs and the never-built `processing_multi_test.cpp` |

**Score:** 9/9 truths verified (0 present, behavior-unverified)

All behavior-dependent truths (single-read stamping, L1-never-recorded, retention/cap eviction, wire round-trip/back-compat) were exercised by named behavioral tests that ran green during this verification — none rely on presence alone.

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `SuperGenius/src/processing/proto/SGProcessing.proto` | `claimed_price` field 6 | ✓ VERIFIED | :23, with D-06-01/02/03 comment block; substantive |
| `SuperGenius/src/account/GeniusNode.cpp` | GetGNUSQuote helper, ProcessCost return, stamping | ✓ VERIFIED | :2694-2720, :2816-2881; wired into ProcessImage |
| `SuperGenius/src/coinprices/LocalPriceManager.hpp` | PriceObservation / PriceHistoryStats / PriceHistoryConfig / QueryHistory + documented empty-after-restart | ✓ VERIFIED | :47-78, :122-123; class comment documents in-memory-only, empty-after-restart, count==0 = "no coverage", local-evidence-not-ruling (D-06-06/D-06-07) |
| `SuperGenius/test/src/price_manager/price_manager_test.cpp` | `*History*` hermetic tests | ✓ VERIFIED | 9 History tests (test:873-1075), all substantive, all PASS |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|----|--------|---------|
| LocalPriceManager.cpp DispatchBatchOnStrand | RecordObservations | call after tier walk, before per-waiter assembly | ✓ WIRED | cpp:274-278, exactly one call site |
| GeniusNode::ProcessImage | GetProcessCost quote | `task.set_claimed_price(cost.quote.price)` — no second GetGNUSPrice | ✓ WIRED | cpp:2720; `GetGNUSPrice` has no ProcessImage reference (only its own definition at :2873) |
| GeniusNode::GetGNUSPrice | GetGNUSQuote | thin wrapper | ✓ WIRED | cpp:2877 |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| History suite (9 tests) | `price_manager_test.exe --gtest_filter=*History*` | `[ PASSED ] 9 tests.` | ✓ PASS |
| Claim stamping + wire round-trip + back-compat (3 tests) | `account_management_test.exe --gtest_filter="*ClaimedPrice*:TaskClaimedPriceWire.*"` | `[ PASSED ] 3 tests.` (incl. 5261 ms escrow-sequencing test) | ✓ PASS |

(Orchestrator's full slice `price_|account_management_test|processing_nodes_test|child_tokens_test` — 8/8 via ctest — corroborates; verifier re-ran the named tests above independently.)

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|---------------------|----------|
| WIRE-01 | 06-02 | backward-compatible `claimed_price` (double) field; escrow DAG timestamp as reference time; old messages parse | ✓ SATISFIED | Truth 1, 2 |
| WIRE-02 | 06-02 | ProcessImage stamps `claimed_price` from the same quote that produced the escrow cost | ✓ SATISFIED | Truth 3 |
| HIST-01 | 06-01 | bounded, timestamped history of fetched genius-ai quotes with min/max-over-window queries | ✓ SATISFIED | Truths 5, 6, 7 |
| HIST-02 | 06-01 | safe degradation when empty after restart (documented) | ✓ SATISFIED | Truth 6 + header docs + `HistoryEmptyOnFreshManagerReturnsZeroCount` |

Orphaned requirements: none — REQUIREMENTS.md maps exactly WIRE-01/02, HIST-01/02 to Phase 6 and the two plans claim all four. REQUIREMENTS wording (WIRE-01/02, D-01, D-03) and ROADMAP criterion 2 were aligned to D-06-02 as planned; VAL-03's `price_timestamp` mention is Phase-7 wording deliberately untouched.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| SuperGenius/src/account/GeniusNode.cpp | 2757 | `//TODO - Make it async to post the job data...` | ℹ️ Info | Pre-existing (git blame: `4a72b7e221`, 2026-05-20 — predates the phase); not on any phase-modified path; not introduced by this phase |
| SuperGenius/test/src/processing_multi/processing_multi_test.cpp | 291, 361 | non-`.minions` `GetProcessCost` callers | ℹ️ Info | Target never built (absent from `test/src/CMakeLists.txt` add_subdirectory list — confirmed) and already uncompilable before the phase; documented in deferred-items.md; plan explicitly scoped it out |

No `TBD`/`FIXME`/`XXX` in any phase file. No mutex, no persistence/file-IO in LocalPriceManager. No placeholder/empty-return stubs found on phase paths.

### Human Verification Required

None. All must-haves have codebase evidence plus passing named behavioral tests; no UI/visual/external-service items. (Caveat, not a gate: the GeniusSDK binary is not built on this host; its 2-line `.minions` unwrap is verified by diff/type inspection per the plan's designated grep verification — the change is type-preserving, `uint64_t → uint64_t`.)

### Gaps Summary

No gaps. All 9 merged must-have truths verified with file/line anchors and green behavioral tests; all 4 phase requirements satisfied; roadmap SC1–SC3 met. Deferred context (documented in `deferred-items.md`, all pre-existing/out-of-scope, none phase-introduced): (a) `ConcurrentGetQuotesAcrossThreadsAllResolve` flake under full-suite load (unrelated path — synthetic non-genius-ai ids), (b) historical `genius_node` UPnP compile breakage (line 2307, merge `f44199411`, before the phase base; test targets restored by `7c50b8d60` and verified green here), (c) `processing_multi_test.cpp` stale callers. Phase 7 owns claimed-price validation (D-06-04) — correctly absent here.

---

_Verified: 2026-10-06T02:05:00Z_
_Verifier: the agent (gsd-verifier)_
