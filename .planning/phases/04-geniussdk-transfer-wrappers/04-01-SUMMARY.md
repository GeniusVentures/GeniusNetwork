---
phase: 04-geniussdk-transfer-wrappers
plan: 01
subsystem: api
tags: [geniussdk, transfer, child-wallet, c-api, ffi]

# Dependency graph
requires:
  - phase: 03-parent-child-transfer-authority
    provides: "GeniusNode::TransferFunds fire-and-forget overload (D-61) and new GeniusNode::RecoverFromChild fire-and-forget overload (D-62/CONS-02), plus the CheckParentChildAuthority consensus gate enforcing D-21 destination restriction"
provides:
  - "GeniusSDKFundChild / GeniusSDKFundChildGNUS C API wrappers exposing main-to-child fund transfer (SDKT-01)"
  - "GeniusSDKRecoverFromChild / GeniusSDKRecoverFromChildGNUS C API wrappers exposing main-recover-from-child transfer (SDKT-02)"
  - "All 4 new functions reuse existing GeniusNodeReturnValue_t codes, no new enum value (SDKT-03/D-69)"
affects: [geniuswallet-integration, future-sdk-consumers]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Raw-amount primary function + GNUS-string sibling that parses via ParseTokens then delegates (mirrors GeniusSDKTransfer/GeniusSDKTransferGNUS)"
    - "lock_guard<recursive_mutex> + do{}while(0) early-break error handling (every GeniusSDK.cpp wrapper)"

key-files:
  created: []
  modified:
    - GeniusSDK/src/GeniusSDK.h
    - GeniusSDK/src/GeniusSDK.cpp

key-decisions:
  - "GeniusSDKFundChild calls TransferFunds(amount, destination, token_id) - amount first, matching TransferFunds's own signature order"
  - "GeniusSDKRecoverFromChild calls RecoverFromChild(child_address, amount, token_id) - child_address FIRST, opposite order from the wrapper's own (amount, child_address, token_id) parameter list, matching GeniusNode::RecoverFromChild's actual signature"
  - "No new GeniusNodeReturnValue enum value added; both new function families reuse GENIUS_NODE_ERROR_TRANSFER for submission failures (D-69)"
  - "Refreshed a stale locally-installed SuperGenius header copy (SuperGenius/build/Windows/Release/SuperGenius/include/account/GeniusNode.hpp) via cmake --install so GeniusSDK could compile against Phase 3's RecoverFromChild declarations - pre-existing build/install staleness gap, not caused by this plan's own file changes"

patterns-established:
  - "Child-wallet transfer wrappers section marker: /* --- Child Wallet Transfers (v2.3) --- */, placed immediately after the v2.2 Child Wallet Interfaces block"

requirements-completed: [SDKT-01, SDKT-02, SDKT-03]

coverage:
  - id: D1
    description: "GeniusSDKFundChild/GeniusSDKFundChildGNUS declared in GeniusSDK.h and implemented in GeniusSDK.cpp, wrapping GeniusNode::TransferFunds with the child's address as destination"
    requirement: "SDKT-01"
    verification:
      - kind: other
        ref: "grep structural checks (exact call-site argument order) - GeniusSDK/src/GeniusSDK.h and GeniusSDK.cpp"
        status: pass
      - kind: other
        ref: "cmake --build GeniusSDK/build/Windows/Release --target GeniusSDK --config Release"
        status: pass
    human_judgment: false
  - id: D2
    description: "GeniusSDKRecoverFromChild/GeniusSDKRecoverFromChildGNUS declared in GeniusSDK.h and implemented in GeniusSDK.cpp, wrapping GeniusNode::RecoverFromChild with correct (child_address, amount, token_id) call order; doc comments carry the D-67 fire-and-forget/D-21-observability @note"
    requirement: "SDKT-02"
    verification:
      - kind: other
        ref: "grep structural checks (exact call-site argument order, @note presence) - GeniusSDK/src/GeniusSDK.h and GeniusSDK.cpp"
        status: pass
      - kind: other
        ref: "cmake --build GeniusSDK/build/Windows/Release --target GeniusSDK --config Release"
        status: pass
    human_judgment: false
  - id: D3
    description: "All 4 new functions return only pre-existing GeniusNodeReturnValue_t codes (GENIUS_NODE_RET_OK, GENIUS_NODE_ERROR_NOT_INITIALIZED, GENIUS_NODE_INVALID_ARGUMENT, GENIUS_NODE_ERROR_TRANSFER) - no new enum value introduced"
    requirement: "SDKT-03"
    verification:
      - kind: other
        ref: "manual review of GeniusSDK.h enum block - no new GeniusNodeReturnValue member added"
        status: pass
    human_judgment: false

duration: 20min
completed: 2026-07-21
status: complete
---

# Phase 4 Plan 01: GeniusSDK Transfer Wrappers Summary

**4 new thin C-API wrappers (GeniusSDKFundChild/GNUS, GeniusSDKRecoverFromChild/GNUS) expose Phase 3's TransferFunds/RecoverFromChild to external callers, reusing all existing GeniusNodeReturnValue_t codes**

## Performance

- **Duration:** ~20 min
- **Completed:** 2026-07-21
- **Tasks:** 2 completed
- **Files modified:** 2 (GeniusSDK/src/GeniusSDK.h, GeniusSDK/src/GeniusSDK.cpp)

## Accomplishments

- Declared and documented 4 new public C API functions in `GeniusSDK.h`: `GeniusSDKFundChild`, `GeniusSDKFundChildGNUS`, `GeniusSDKRecoverFromChild`, `GeniusSDKRecoverFromChildGNUS`, each under a new `/* --- Child Wallet Transfers (v2.3) --- */` section marker
- Implemented all 4 functions in `GeniusSDK.cpp` following the existing lock_guard + do/while(0) early-break pattern used by every wrapper in the file
- `GeniusSDKFundChild` calls `TransferFunds(amount, destination, token_id)` (amount first); `GeniusSDKRecoverFromChild` calls `RecoverFromChild(child_address, amount, token_id)` (child_address first) - the two underlying `GeniusNode` methods have different argument orders, and both call sites were verified to match exactly
- Both GNUS-string sibling functions parse the amount via `ParseTokens` then delegate to their raw-amount primary function, exactly mirroring `GeniusSDKTransferGNUS` -> `GeniusSDKTransfer`
- `GeniusSDKRecoverFromChild`'s and `GeniusSDKRecoverFromChildGNUS`'s doc comments carry an explicit `@note` documenting the D-67 fire-and-forget/D-21-observability limitation
- No new `GeniusNodeReturnValue` enum value introduced; both new function families reuse `GENIUS_NODE_ERROR_TRANSFER` (D-69)
- Verified the `GeniusSDK` static library target builds cleanly with both new functions linked against `sgns::genius_node`'s existing symbols

## Task Commits

Each task was committed atomically inside the `GeniusSDK` submodule's own git repo (branch `dev_childwallet`):

1. **Task 1: Declare 4 new GeniusSDK C API functions in GeniusSDK.h** - `35b633a` (feat)
2. **Task 2: Implement the 4 new GeniusSDK C API functions in GeniusSDK.cpp** - `de2c436` (feat)

**Parent repo (GeniusNetwork) gitlink + plan metadata:** committed separately as part of the docs commit that closes this plan (see final commit below).

## Files Created/Modified

- `GeniusSDK/src/GeniusSDK.h` - Added 4 new function declarations with Doxygen doc comments under a new `/* --- Child Wallet Transfers (v2.3) --- */` section marker, placed after `GeniusSDKGetChildBalanceAll` and before `GNUS_EXPORT_END`
- `GeniusSDK/src/GeniusSDK.cpp` - Added 4 new function implementations after `GeniusSDKGetChildBalanceAll`, following the exact lock/do-while/has_value skeleton used by every existing wrapper

## Decisions Made

- `GeniusSDKFundChild`'s call into `TransferFunds` uses `(amount, std::string(child_address), token_id)` - no reordering needed since this matches `TransferFunds`'s own signature.
- `GeniusSDKRecoverFromChild`'s call into `RecoverFromChild` uses `(std::string(child_address), amount, token_id)` - `child_address` FIRST, the opposite order from the wrapper's own `(amount, child_address, token_id)` parameter list, because `GeniusNode::RecoverFromChild`'s actual signature takes `child_address` first. This was called out explicitly in both the plan and pattern map and verified via a targeted grep check.
- Both submission-failure paths return `GENIUS_NODE_ERROR_TRANSFER` - no new `GENIUS_NODE_ERROR_RECOVERY` value, per D-69.
- Section marker placement: grouped with the existing v2.2 Child Wallet Interfaces block (after `GeniusSDKGetChildBalanceAll`) rather than near `GeniusSDKTransfer`/`GeniusSDKTransferGNUS`, keeping all child-wallet-intent calls adjacent - consistent with the file's existing organization (planner's discretion per 04-CONTEXT.md).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking build issue] Stale locally-installed SuperGenius header blocked GeniusSDK build verification**
- **Found during:** Task 2 (`cmake --build GeniusSDK/build/Windows/Release --target GeniusSDK --config Release` verification step)
- **Issue:** The GeniusSDK build resolves `SuperGenius/account/GeniusNode.hpp` via a locally-installed copy at `SuperGenius/build/Windows/Release/SuperGenius/include/account/GeniusNode.hpp` (populated by `cmake --install`/`supergenius_install`), not the submodule's `src/account/GeniusNode.hpp` directly. That installed copy was last refreshed 2026-07-17, predating Phase 3's `RecoverFromChild` additions (2026-07-20/21), so the build failed with `error C2039: 'RecoverFromChild': is not a member of 'sgns::GeniusNode'`.
- **Fix:** Ran `cmake --install SuperGenius/build/Windows/Release --config Release --prefix "W:/gnus/GeniusNetwork/SuperGenius/build/Windows/Release/SuperGenius"` to refresh the installed header tree (header-only install; no relink of `genius_node.lib` was required since the `GeniusSDK` target only compiles, it does not link against `genius_node`).
- **Files modified:** None in the repo (only a local build/install artifact directory was refreshed - not tracked in git).
- **Verification:** Re-ran `cmake --build GeniusSDK/build/Windows/Release --target GeniusSDK --config Release` - succeeded with zero errors.
- **Committed in:** N/A (build-artifact refresh only, no source changes to commit).

---

**Total deviations:** 1 auto-fixed (Rule 3, build/install staleness).
**Impact on plan:** Necessary to complete the plan's own build verification step; no scope creep into SuperGenius source, no business logic touched.

## Issues Encountered

None beyond the build/install staleness documented above.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- All 3 phase requirements (SDKT-01, SDKT-02, SDKT-03) are implemented and build-verified.
- v2.3 milestone's Active requirements list is now fully addressed at the code level; remaining milestone work is verification/closeout (see Operator Next Steps in STATE.md).
- No dedicated `GeniusSDK/test` unit tests were added, per project convention (memory: `feedback_geniussdk_no_dedicated_tests.md`) and this milestone's explicit out-of-scope note - the underlying `TransferFunds`/`RecoverFromChild` logic is already covered by SuperGenius's `registration_transaction_test.exe` (Phase 3).
- Anyone consuming this SDK build must ensure their local SuperGenius install tree is refreshed (`cmake --install`) after any `GeniusNode.hpp`/`.cpp` change before rebuilding `GeniusSDK` - this staleness trap is not new to this plan and could recur in future phases that touch both submodules in the same session.

---
*Phase: 04-geniussdk-transfer-wrappers*
*Completed: 2026-07-21*

## Self-Check: PASSED

- FOUND: GeniusSDK/src/GeniusSDK.h
- FOUND: GeniusSDK/src/GeniusSDK.cpp
- FOUND: 35b633a (git -C GeniusSDK log)
- FOUND: de2c436 (git -C GeniusSDK log)
