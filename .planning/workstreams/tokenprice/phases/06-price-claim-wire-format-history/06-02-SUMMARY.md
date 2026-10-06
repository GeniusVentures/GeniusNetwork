---
phase: 06-price-claim-wire-format-history
plan: "02"
subsystem: api
tags: [protobuf, wire-format, price-claim, escrow, cpp, proto3]

requires:
  - phase: 06-price-claim-wire-format-history/06-01
    provides: LocalPriceManager single-read GetQuotes surface used by GetGNUSQuote
provides:
  - SGProcessing::Task.claimed_price (double, field 6) wire field
  - GeniusNode::ProcessCost {minions, PriceQuote} single-read cost quote plumbing
  - GeniusNode::GetGNUSQuote() one-shot quote helper (GetGNUSPrice thin wrapper)
  - ProcessImage stamps claimed_price from the escrow-sizing quote (WIRE-02)
  - Migrated GetProcessCost callers (GeniusSDK + 3 SuperGenius test files)
affects: [07-price-validator, 08-consensus-integration, GeniusSDK, GeniusWallet]

actuals:
  tokens: 9809   # chars/4 over realized diffs (SuperGenius 31416 + GeniusSDK 933 + planning 6888); estimate was 70000
  tasks: 3
  commits: 3     # SuperGenius (7c50b8d60, a8e26d2d6, 9fcdabf5a) + GeniusSDK (9f2e955) + parent docs commit

tech-stack:
  added: []
  patterns:
    - "ProcessCost struct return: one GetQuotes read both sizes the escrow and supplies the wire claim (no second fetch)"
    - "Sequencing price stub: Gnus envelope with stale fetchedAt (>300s) defeats L1 freshness so consecutive fetches always hit the scripted tier"
    - "TU-local friend accessor idiom extended: AccountManagementTestAccess (GeniusNode) + MultiAccountTestAccess (TransactionManager) for task/escrow observation"

key-files:
  created: []
  modified:
    - SuperGenius/src/processing/proto/SGProcessing.proto
    - SuperGenius/src/account/GeniusNode.hpp
    - SuperGenius/src/account/GeniusNode.cpp
    - SuperGenius/test/src/account/account_management_test.cpp
    - SuperGenius/test/src/processing_nodes/processing_nodes_test.cpp
    - SuperGenius/test/src/processing_nodes/child_tokens_test.cpp
    - GeniusSDK/src/GeniusSDK.cpp
    - .planning/workstreams/tokenprice/REQUIREMENTS.md
    - .planning/workstreams/tokenprice/ROADMAP.md

key-decisions:
  - "claimed_price is double (never float) so Phase 7's CalculateCostMinions(size, claimed)==escrow equality is exact"
  - "No timestamp wire field (D-06-02): escrow DAGStruct.timestamp via task.escrow_path is the validation reference time"
  - "GetGNUSQuote calls GetQuotes directly (not GetCoinprice) so the full PriceQuote survives the single read"
  - "Failure keeps minions==0 legacy convention; ProcessImage funds<=0 check unchanged"

patterns-established:
  - "Single-read quote plumbing via ProcessCost struct (WIRE-02 guarantee)"
  - "Non-fresh Gnus-envelope stub body for multi-fetch sequencing without TTL waits"

requirements-completed: [WIRE-01, WIRE-02]

coverage:
  - id: D1
    description: "Task wire field: claimed_price round-trips bit-exactly and old (fields 1-5) messages parse as 0.0"
    requirement: WIRE-01
    verification:
      - kind: unit
        ref: "SuperGenius/test/src/account/account_management_test.cpp#TaskClaimedPriceWire.RoundTripPreservesDouble"
        status: pass
      - kind: unit
        ref: "SuperGenius/test/src/account/account_management_test.cpp#TaskClaimedPriceWire.OldMessageParsesAsZero"
        status: pass
    human_judgment: false
  - id: D2
    description: "ProcessImage stamps claimed_price from the exact quote that sized the escrow (P1 then P2 sequencing proves single read)"
    requirement: WIRE-02
    verification:
      - kind: integration
        ref: "SuperGenius/test/src/account/account_management_test.cpp#AccountManagement.ClaimedPriceMatchesEscrowQuote"
        status: pass
    human_judgment: false
  - id: D3
    description: "Every GetProcessCost caller migrated to .minions (public SDK C API unchanged)"
    verification:
      - kind: unit
        ref: "repo-wide GetProcessCost grep (plan Task 2 automated): 0 code hits; GeniusSDK/Wallet builds not runnable here, grep is the verification per plan"
        status: pass
    human_judgment: false
  - id: D4
    description: "REQUIREMENTS/ROADMAP wording aligned to D-06-02 (claimed price only; timestamp = escrow DAG timestamp)"
    verification:
      - kind: unit
        ref: "Select-String verify per plan: ok (8 matches), stale WIRE wording clean"
        status: pass
    human_judgment: false

duration: 25min
completed: 2026-10-05
status: complete
---

# Phase 06 Plan 02: Claimed Price Wire Format Summary

**Task.claimed_price (double, proto field 6) stamped by ProcessImage from the single GetQuotes read that sized the escrow, with all callers migrated to the ProcessCost struct.**

## Performance

- **Duration:** 25 min
- **Started:** 2026-10-05T21:21:43Z
- **Completed:** 2026-10-06T01:46:57Z
- **Tasks:** 3/3
- **Files modified:** 9

## Accomplishments

- `SGProcessing::Task` gains `double claimed_price = 6` (proto3 back-compat; old messages parse as 0.0) — WIRE-01
- `GetProcessCost` returns `ProcessCost{minions, PriceQuote}` built from ONE `GetGNUSQuote()` read; `ProcessImage` stamps `task.set_claimed_price(cost.quote.price)` and never re-fetches — WIRE-02 / D-06-01
- Hermetic tracer `ClaimedPriceMatchesEscrowQuote`: sequencing stub serves P1 then P2; posted task claims P1 and the escrow hold equals `CalculateCostMinions(4860000, P1)` even after the price moves
- Wire tests `RoundTripPreservesDouble` + `OldMessageParsesAsZero`; every `GetProcessCost` caller (GeniusSDK ~707/~728, 3 SuperGenius test files) migrated to `.minions` with the exported C API unchanged
- REQUIREMENTS/ROADMAP wording aligned to D-06-02 (no timestamp field; escrow DAG timestamp is the reference)

## Task Commits

Each task was committed atomically:

1. **Task 0 (Rule 1 baseline fix): UPnP factory removal compile fix** - `7c50b8d60` (fix, SuperGenius)
2. **Task 1: Tracer — quote → escrow sizing → Task.claimed_price** - `a8e26d2d6` (feat, SuperGenius; includes Rule 2 harness repair)
3. **Task 2: Wire tests + caller migration** - `9fcdabf5a` (test, SuperGenius) + `9f2e955` (refactor, GeniusSDK)
4. **Task 3: REQUIREMENTS/ROADMAP wording** - parent docs commit (with SUMMARY + submodule pointers)

**Plan metadata:** parent commit `docs(06-02): complete claimed price wire format plan`

_TDD: Task 1 ran RED first (error C2039 `claimed_price` / `ResetPriceManagerForTest` at build 21:36) before the production change; Task 2's OldMessageParsesAsZero covered new back-compat behavior._

## Files Created/Modified

- `SuperGenius/src/processing/proto/SGProcessing.proto` — `claimed_price = 6` with D-06-02 rationale comment
- `SuperGenius/src/account/GeniusNode.hpp` — `ProcessCost` struct, `GetGNUSQuote`, `ResetPriceManagerForTest` seam, PriceQuote include
- `SuperGenius/src/account/GeniusNode.cpp` — struct-return `GetProcessCost`, `GetGNUSQuote` (direct `GetQuotes`), thin `GetGNUSPrice`, `ProcessImage` stamping + `cost.minions` check
- `SuperGenius/test/src/account/account_management_test.cpp` — tracer test, 2 wire tests, harness repair, `.minions` migration
- `SuperGenius/test/src/processing_nodes/processing_nodes_test.cpp` — `.minions` at 373/383/526
- `SuperGenius/test/src/processing_nodes/child_tokens_test.cpp` — `.minions` at 597
- `GeniusSDK/src/GeniusSDK.cpp` — `.minions` at ~707/~728 (signatures/FFI untouched)
- `.planning/workstreams/tokenprice/REQUIREMENTS.md` — D-01/D-03/WIRE-01/WIRE-02 reworded to D-06-02; WIRE-01/02 checked
- `.planning/workstreams/tokenprice/ROADMAP.md` — Phase 6 criterion 2, plan checklist 2/2, summary line

## Decisions Made

- `GetGNUSQuote` calls `GetOrCreatePriceManager()->GetQuotes` directly rather than going through `GetCoinprice`'s map flattening, per the plan action ("calls GetQuotes once") — the full quote survives the single read
- Sequencing harness: second `HttpStubServer` + env repoint + `ResetPriceManagerForTest()`; Gnus-envelope bodies carry a >300s-old `fetchedAt` so L1 never serves a stale-band quote and every fetch hits the scripted tier (no 60s TTL wait, no production change)
- Escrow observation via `MultiAccountTestAccess::GetEscrowTransaction` → `TransactionManager::GetTransactionByHash` (private API; the friend already exists in TransactionManager.hpp) + `EscrowTransaction::GetAmount()` — avoids fragile balance-delta assertions

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] genius_node_test failed to compile at baseline (UPnP factory removal)**
- **Found during:** pre-Task 1 baseline build
- **Issue:** thirdparty gnu_upnp dropped `UPNP::New()`; `InitUPNP`/`RefreshUPNP` used it, producing C2039 (`New`, `GetIGD`, `__this`, `OpenPort`) in genius_node_test — blocking every test target (the known pre-existing issue the 06-01 executor flagged)
- **Fix:** construct via `std::make_shared<upnp::UPNP>()` at both call sites (public ctor + `enable_shared_from_this` remain)
- **Files modified:** SuperGenius/src/account/GeniusNode.cpp
- **Commit:** 7c50b8d60

**2. [Rule 2 - Blocking] account_management_test did not compile at baseline (stale harness)**
- **Found during:** pre-Task 1 baseline build (after Deviation 1 unblocked the library)
- **Issue:** `AccountManagementTestAccess::SetGNUSPrice` seeded `m_tokenPriceCache`, a member deleted by 04-01 (`79a2f6e1c`) — the plan's "Phase 4 hermetic stub harness" reference was stale; the target could not build before or after the planned change
- **Fix:** replaced with friend accessors: `GetPostedTask` (task queue), `MultiAccountTestAccess::GetEscrowTransaction` (escrow amount), `ResetPriceManager` (price-manager reset seam on GeniusNode for stub sequencing); `SetPayoutAddress` now warms pricing hermetically via `GetGNUSPrice` against the fixture stub (passes, ~33s)
- **Files modified:** SuperGenius/test/src/account/account_management_test.cpp, SuperGenius/src/account/GeniusNode.hpp (seam)
- **Commit:** a8e26d2d6

**3. [Rule 3 - Process] first Task-0 commit accidentally included Task 1 production changes**
- **Issue:** whole-file `git add` captured uncommitted Task 1 work; commit message/atomicity wrong
- **Fix:** mixed-reset, isolated the UPnP-only diff, recommitted `7c50b8d60`, then restored the full file for the Task 1 commit — verified both commits' diffs are scoped correctly

### Wordings verified, no code change needed

- Pre-existing `genius_node` (non-test) target: not built by this plan's targets; left untouched per instructions.

## Pre-existing Issues (out of scope, documented per plan)

- `SuperGenius/test/src/processing_multi/processing_multi_test.cpp` is intentionally NOT edited: it is registered in no CMakeLists (never built) and already fails to compile independent of this change — it passes a `std::string` to `GetProcessCost(const ProcessingManager&)` (no implicit conversion). Its 2 call sites (~291, ~361) would need `.minions` if ever revived. `cost` there is only streamed and used in `cost - ( cost * 65 ) / 100`.
- Repo-wide `GetProcessCost` grep result: every live caller uses `.minions`. Remaining pattern hits are historical prose in `GeniusSDK/.planning/codebase/CONCERNS.md:205` and `GeniusSDK/.planning/phases/02-verification-documentation/02-REVIEW.md:147` (docs, not code).
- GeniusSDK/GeniusWallet builds are not runnable in this environment; the grep is the SDK verification per plan (exported C API signatures unchanged — only `.minions` appended to internal call expressions).
- `SetPayoutAddress` runtime grew from cache-seeded (~instant price) to stub-served (~33s) — hermetic but slower; within its existing 300s escrow timeout.

## Auth Gates

None.

## Known Stubs

None — all deliverables are wired and verified.

## Self-Check: PENDING

