---
type: quick
plan: 01
subsystem: api
tags: [geniussdk, child-wallet, lifecycle, c-api, detach, revoke, replace-main]

# Dependency graph
requires:
  - phase: 05-child-wallet-lifecycle-states
    provides: "GeniusNode::DetachChild/ReplaceMain/RevokeChild plus consensus-side enforcement (CheckParentChildAuthority revoke branch, FilterRegistration gate 3b's supersedes_sequence check)"
provides:
  - "GeniusSDKDetachChild C API wrapper exposing child-initiated Detach (D-35)"
  - "GeniusSDKReplaceMain C API wrapper exposing child-initiated Replace-Main (D-37)"
  - "GeniusSDKRevokeChild C API wrapper exposing main-initiated Revoke (D-36)"
  - "All 3 new functions reuse existing GeniusNodeReturnValue_t codes, no new enum value"
affects: [geniuswallet-integration, future-sdk-consumers]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "lock_guard<recursive_mutex> + do{}while(0) early-break error handling (every GeniusSDK.cpp wrapper)"
    - "Metadata-struct-by-value argument gets no null-check (mirrors GeniusSDKRegisterChild); const char* address args get the address == nullptr || address[0] == '\\0' check (mirrors GeniusSDKRecoverFromChild)"

key-files:
  created: []
  modified:
    - GeniusSDK/src/GeniusSDK.h
    - GeniusSDK/src/GeniusSDK.cpp

key-decisions:
  - "GeniusSDKDetachChild has no wrapper-level precondition check since its only argument is a by-value GeniusRegistrationMetadata struct - matches GeniusSDKRegisterChild's own no-check-on-the-struct convention"
  - "All 3 functions reuse GENIUS_NODE_ERROR_REGISTRATION for submission failures - no new enum value added, consistent with D-69's precedent from Phase 4"
  - "GeniusSDKRevokeChild's doc comment carries an explicit @note documenting the fire-and-forget/consensus-finalization-only-rejection limitation, mirroring GeniusSDKRecoverFromChild's D-21/D-67 caveat"
  - "Refreshed the stale locally-installed SuperGenius header (SuperGenius/build/Windows/Release/SuperGenius/include/account/GeniusNode.hpp) via cmake --install before building GeniusSDK - the exact same known pitfall documented in Phase 4 Plan 01, recurred as predicted by the plan"

patterns-established:
  - "Child-wallet lifecycle wrappers section marker: /* --- Child Wallet Lifecycle (v2.4) --- */, placed immediately after the v2.3 Child Wallet Transfers block and before GNUS_EXPORT_END"

requirements-completed: []

coverage:
  - id: D1
    description: "GeniusSDKDetachChild declared in GeniusSDK.h and implemented in GeniusSDK.cpp, calling GeniusNodeInstance->DetachChild(proto_metadata) with exactly one argument (auto-derive overload)"
    requirement: "D-35"
    verification:
      - kind: other
        ref: "grep structural checks (exact call-site argument count) - GeniusSDK/src/GeniusSDK.h and GeniusSDK.cpp"
        status: pass
      - kind: other
        ref: "cmake --build GeniusSDK/build/Windows/Release --target GeniusSDK --config Release"
        status: pass
    human_judgment: false
  - id: D2
    description: "GeniusSDKReplaceMain declared in GeniusSDK.h and implemented in GeniusSDK.cpp, calling GeniusNodeInstance->ReplaceMain(new_main_address, proto_metadata) with exactly two arguments (auto-derive overload)"
    requirement: "D-37"
    verification:
      - kind: other
        ref: "grep structural checks (exact call-site argument count) - GeniusSDK/src/GeniusSDK.h and GeniusSDK.cpp"
        status: pass
      - kind: other
        ref: "cmake --build GeniusSDK/build/Windows/Release --target GeniusSDK --config Release"
        status: pass
    human_judgment: false
  - id: D3
    description: "GeniusSDKRevokeChild declared in GeniusSDK.h and implemented in GeniusSDK.cpp, calling GeniusNodeInstance->RevokeChild(child_address) with exactly one argument (fire-and-forget overload); doc comment carries the fire-and-forget/consensus-finalization @note"
    requirement: "D-36"
    verification:
      - kind: other
        ref: "grep structural checks (exact call-site argument count, @note presence) - GeniusSDK/src/GeniusSDK.h and GeniusSDK.cpp"
        status: pass
      - kind: other
        ref: "cmake --build GeniusSDK/build/Windows/Release --target GeniusSDK --config Release"
        status: pass
    human_judgment: false
  - id: D4
    description: "All 3 new functions return only pre-existing GeniusNodeReturnValue_t codes - no new enum value introduced"
    requirement: "N/A"
    verification:
      - kind: other
        ref: "manual review of GeniusSDK.h enum block - no new GeniusNodeReturnValue member added"
        status: pass
    human_judgment: false

duration: 25min
completed: 2026-07-23
status: complete
---

# Quick Task 260723-2tc: Add GeniusSDKDetachChild/GeniusSDKReplaceMain/GeniusSDKRevokeChild Summary

**3 new thin C-API wrappers expose Phase 5's child-wallet lifecycle transitions (Detach/Replace-Main/Revoke) to external SDK callers, reusing all existing GeniusNodeReturnValue_t codes**

## Performance

- **Duration:** ~25 min
- **Completed:** 2026-07-23
- **Tasks:** 2 completed
- **Files modified:** 2 (GeniusSDK/src/GeniusSDK.h, GeniusSDK/src/GeniusSDK.cpp)

## Accomplishments

- Declared and documented 3 new public C API functions in `GeniusSDK.h`: `GeniusSDKDetachChild`, `GeniusSDKReplaceMain`, `GeniusSDKRevokeChild`, under a new `/* --- Child Wallet Lifecycle (v2.4) --- */` section marker placed after the v2.3 Child Wallet Transfers block
- Implemented all 3 functions in `GeniusSDK.cpp` following the existing lock_guard + do/while(0) early-break pattern used by every wrapper in the file
- `GeniusSDKDetachChild` calls `DetachChild(proto_metadata)` (1 arg, resolving to the auto-derive overload, not the 3-arg manual-sequence one)
- `GeniusSDKReplaceMain` calls `ReplaceMain(new_main_address, proto_metadata)` (2 args, resolving to the auto-derive overload, not the 4-arg manual-sequence one)
- `GeniusSDKRevokeChild` calls `RevokeChild(child_address)` (1 arg, resolving to the fire-and-forget overload, not the 2-arg timeout one)
- `GeniusSDKRevokeChild`'s doc comment carries an explicit `@note` documenting the fire-and-forget/consensus-finalization-only-rejection limitation, mirroring `GeniusSDKRecoverFromChild`'s D-21/D-67 caveat
- No new `GeniusNodeReturnValue` enum value introduced; all 3 new functions reuse `GENIUS_NODE_ERROR_REGISTRATION` for submission failures
- Updated the existing `GENIUS_NODE_ERROR_REGISTRATION` enum member's inline comment to mention the 3 new lifecycle functions
- Refreshed the stale locally-installed SuperGenius header (predicted-and-confirmed staleness: `grep` for `RevokeChild|DetachChild|ReplaceMain` in the installed header returned 0 matches before refresh, 6 after) via `cmake --install`
- Verified the `GeniusSDK` target builds cleanly (zero errors) against the refreshed `sgns::GeniusNode` declarations

## Task Commits

Each task was committed atomically inside the `GeniusSDK` submodule's own git repo (branch `dev_childwallet`):

1. **Task 1: Declare 3 new GeniusSDK C API functions in GeniusSDK.h** - `640b0c3` (feat)
2. **Task 2: Implement the 3 new GeniusSDK C API functions in GeniusSDK.cpp** - `7289080` (feat)

**Parent repo (GeniusNetwork) gitlink:** bumped in a separate code-only commit `0d2bd92` on branch `dev_persisprocresults`, matching Phase 4's precedent. Docs artifacts (this SUMMARY, STATE.md, PLAN.md) are committed separately by the orchestrator's own docs commit.

## Files Created/Modified

- `GeniusSDK/src/GeniusSDK.h` - Added 3 new function declarations with Doxygen doc comments under a new `/* --- Child Wallet Lifecycle (v2.4) --- */` section marker, placed after `GeniusSDKRecoverFromChildGNUS` and before `GNUS_EXPORT_END`; extended the `GENIUS_NODE_ERROR_REGISTRATION` enum comment
- `GeniusSDK/src/GeniusSDK.cpp` - Added 3 new function implementations appended after `GeniusSDKRecoverFromChildGNUS`, following the exact lock/do-while/has_value skeleton used by every existing wrapper

## Decisions Made

- `GeniusSDKDetachChild`'s only argument is the by-value `GeniusRegistrationMetadata metadata` struct - no null/empty check is applied to it, matching `GeniusSDKRegisterChild`'s own metadata-handling convention (no check on the struct itself, only on accompanying address args).
- `GeniusSDKReplaceMain`'s `new_main_address == nullptr || new_main_address[0] == '\0'` check and `GeniusSDKRevokeChild`'s analogous `child_address` check both mirror `GeniusSDKRecoverFromChild`'s existing idiom exactly, applied before any `GeniusNodeInstance` call.
- All 3 submission-failure paths return `GENIUS_NODE_ERROR_REGISTRATION` - no new enum value, consistent with how Phase 2's `GeniusSDKRegisterChild` already uses this code and Phase 4's D-69 precedent of reusing a single error code per function family.
- Section marker placement: appended immediately after the v2.3 Child Wallet Transfers block (`GeniusSDKRecoverFromChildGNUS`) and before `GNUS_EXPORT_END`, keeping all child-wallet-related declarations adjacent in file order (registration -> transfers -> lifecycle).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking build issue] Stale locally-installed SuperGenius header blocked GeniusSDK build verification**
- **Found during:** Task 2 (`cmake --build GeniusSDK/build/Windows/Release --target GeniusSDK --config Release` verification step)
- **Issue:** Exactly as flagged by the plan's own "KNOWN BUILD PITFALL" note - the GeniusSDK build resolves `SuperGenius/account/GeniusNode.hpp` via a locally-installed copy at `SuperGenius/build/Windows/Release/SuperGenius/include/account/GeniusNode.hpp`, not the submodule's `src/account/GeniusNode.hpp` directly. That installed copy predated Phase 5's `DetachChild`/`ReplaceMain`/`RevokeChild` additions (confirmed via `grep -c "RevokeChild\|DetachChild\|ReplaceMain"` returning 0 before refresh).
- **Fix:** Ran `cmake --install SuperGenius/build/Windows/Release --config Release --prefix "W:/gnus/GeniusNetwork/SuperGenius/build/Windows/Release/SuperGenius"` to refresh the installed header tree (header-only install; no relink of `genius_node.lib` required since `GeniusSDK` only compiles against the header, it does not link against `genius_node`).
- **Files modified:** None in the repo (only a local build/install artifact directory was refreshed - not tracked in git).
- **Verification:** Re-ran the grep check (now 6 matches, confirming refresh) then `cmake --build GeniusSDK/build/Windows/Release --target GeniusSDK --config Release` - succeeded with zero errors.
- **Committed in:** N/A (build-artifact refresh only, no source changes to commit).

**2. [Rule 1 - Formatting fix] Multi-line clang-format-style declaration broke the plan's exact-string grep verification**
- **Found during:** Task 1 verification (initial `grep -c` for the `GeniusSDKReplaceMain` declaration returned 0)
- **Issue:** The first draft of `GeniusSDKReplaceMain`'s declaration was wrapped across two lines with aligned parameter columns (matching the file's clang-format style used elsewhere), but the plan's verification grep expects the exact single-line signature string `GeniusNodeReturnValue_t GeniusSDKReplaceMain( const char *new_main_address, GeniusRegistrationMetadata metadata )`.
- **Fix:** Reformatted the declaration onto a single line to satisfy the plan's structural grep check, matching the exact string the plan specifies (still valid C syntax, no functional change).
- **Files modified:** `GeniusSDK/src/GeniusSDK.h` (line reformatted before the Task 1 commit, so no separate commit was needed).
- **Verification:** Re-ran `grep -c "GeniusNodeReturnValue_t GeniusSDKReplaceMain( const char \*new_main_address, GeniusRegistrationMetadata metadata )" GeniusSDK/src/GeniusSDK.h` - now returns 1.
- **Committed in:** `640b0c3` (fixed before the Task 1 commit was made, not a separate commit).

---

**Total deviations:** 2 auto-fixed (1x Rule 3 build/install staleness, 1x Rule 1 formatting fix to satisfy plan's own grep verification).
**Impact on plan:** Both necessary to complete the plan's own verification steps as written; no scope creep into SuperGenius source, no business logic touched, no new declarations beyond the 3 specified.

## Issues Encountered

None beyond the two auto-fixed deviations documented above.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- All 3 new C API functions (`GeniusSDKDetachChild`, `GeniusSDKReplaceMain`, `GeniusSDKRevokeChild`) are implemented and build-verified against the refreshed SuperGenius header.
- No dedicated `GeniusSDK/test` unit tests were added, per project convention (memory: `feedback_geniussdk_no_dedicated_tests.md`) - the underlying `DetachChild`/`ReplaceMain`/`RevokeChild` logic this plan wraps is already covered by SuperGenius's Phase 5 test suite (`registration_transaction_test.exe`, `child_registration_test.exe`).
- Anyone consuming this SDK build must ensure their local SuperGenius install tree is refreshed (`cmake --install`) after any `GeniusNode.hpp`/`.cpp` change before rebuilding `GeniusSDK` - this staleness trap recurred exactly as predicted from Phase 4 Plan 01 and will likely recur again in future phases that touch both submodules in the same session.
- The GeniusSDK submodule pointer has been bumped in the top-level `GeniusNetwork` repo (commit `0d2bd92`); consumers building from the superproject will pick up the new wrappers on next `git submodule update`.

---
*Quick task: 260723-2tc*
*Completed: 2026-07-23*

## Self-Check: PASSED

- FOUND: GeniusSDK/src/GeniusSDK.h
- FOUND: GeniusSDK/src/GeniusSDK.cpp
- FOUND: 640b0c3 (git -C GeniusSDK log)
- FOUND: 7289080 (git -C GeniusSDK log)
- FOUND: 0d2bd92 (git log, top-level repo)
