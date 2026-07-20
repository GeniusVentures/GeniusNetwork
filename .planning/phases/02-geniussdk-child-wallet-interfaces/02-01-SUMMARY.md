---
phase: 02-geniussdk-child-wallet-interfaces
plan: 01
subsystem: api
tags: [geniussdk, child-wallet, registration, c-api, ffi, protobuf]

# Dependency graph
requires:
  - phase: 01-child-balance-query
    provides: GeniusNode::GetChildBalance (token-filtered + all-tokens), GeniusNode::RegisterChild, GeniusNode::GetRegistrationsForMain
provides:
  - GeniusSDKRegisterChild C API wrapping the auto-derived-sequence RegisterChild overload
  - GeniusSDKGetRegistrationsForMain C API with malloc'd GeniusSDKFree-compatible output array
  - GeniusSDKGetChildBalance / GeniusSDKGetChildBalanceAll C API wrappers
  - GeniusRegistrationMetadata / GeniusRegistrationDiscoveryEntry C structs
  - GENIUS_NODE_ERROR_REGISTRATION error code
affects: [geniuswallet-flutter-integration, external-game-sdk-consumers]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "do/while(0)-guarded status-code wrapper pattern (matches GeniusSDKMint/GeniusSDKTransfer/GeniusSDKPayDev)"
    - "strnlen-bounded std::string construction from fixed-size caller-supplied char arrays (avoids over-read past array bound on non-null-terminated input)"
    - "malloc'd output array + GeniusSDKFree ownership handoff for variable-length discovery results"

key-files:
  created: []
  modified:
    - GeniusSDK/src/GeniusSDK.h
    - GeniusSDK/src/GeniusSDK.cpp

key-decisions:
  - "GENIUS_SDK_MAX_METADATA_STRING_SIZE=128 bound for game_id/publisher_id/dev_wallet — sized as opaque strings, not address-shaped (GENIUS_SDK_ADDRESS_SIZE), matching plan guidance"
  - "GeniusSDKRegisterChild wraps only the 2-arg auto-derived-sequence RegisterChild overload; the 3-arg manual-sequence overload is intentionally not exposed"
  - "Zero registrations from GeniusSDKGetRegistrationsForMain is GENIUS_NODE_RET_OK with *out_count=0, not a failure"

requirements-completed: [SDKR-01, SDKR-02, SDKR-03, SDKR-04, SDKB-01, SDKB-02]

coverage:
  - id: D1
    description: "GeniusSDKRegisterChild exposes GeniusNode::RegisterChild's auto-derived-sequence overload via the C API, returning GENIUS_NODE_RET_OK/GENIUS_NODE_ERROR_NOT_INITIALIZED/GENIUS_NODE_INVALID_ARGUMENT/GENIUS_NODE_ERROR_REGISTRATION"
    requirement: "SDKR-01"
    verification:
      - kind: other
        ref: "grep -c GeniusSDKRegisterChild GeniusSDK/src/GeniusSDK.h && grep -A2 GeniusSDKRegisterChild GeniusSDK/src/GeniusSDK.h | grep -c sequence (returns 0, proving manual-sequence overload not exposed)"
        status: pass
    human_judgment: true
    rationale: "GeniusSDK static-lib build could not be compiled end-to-end due to a pre-existing SuperGenius/evmrelay CMake packaging gap unrelated to this task (see Deferred Issues); code correctness was verified by manual line-by-line signature cross-check against GeniusNode.hpp, not by compilation, so a human should confirm once the build environment issue is resolved."
  - id: D2
    description: "GeniusSDKGetRegistrationsForMain enumerates a main wallet's registered children via GeniusNode::GetRegistrationsForMain, with a malloc'd GeniusSDKFree-compatible output array"
    requirement: "SDKR-02"
    verification:
      - kind: other
        ref: "grep -c GeniusNodeInstance->GetRegistrationsForMain GeniusSDK/src/GeniusSDK.cpp"
        status: pass
    human_judgment: true
    rationale: "Same build-verification blocker as D1 — logic verified by inspection, not compiled."
  - id: D3
    description: "GeniusSDKGetChildBalance (token-filtered) and GeniusSDKGetChildBalanceAll (all-tokens) wrap GeniusNode::GetChildBalance's two overloads"
    requirement: "SDKB-01"
    verification:
      - kind: other
        ref: "grep -c GeniusNodeInstance->GetChildBalance GeniusSDK/src/GeniusSDK.cpp (== 2)"
        status: pass
    human_judgment: true
    rationale: "Same build-verification blocker as D1 — logic verified by inspection, not compiled."

duration: 20min
completed: 2026-07-18
status: complete
---

# Phase 2 Plan 01: GeniusSDK Child Wallet Interfaces Summary

**Added GeniusSDKRegisterChild, GeniusSDKGetRegistrationsForMain, GeniusSDKGetChildBalance, and GeniusSDKGetChildBalanceAll to the public GeniusSDK C API, wrapping the existing GeniusNode::RegisterChild/GetRegistrationsForMain/GetChildBalance logic with strnlen-bounded proto conversion and a malloc'd/GeniusSDKFree discovery-array pattern.**

## Performance

- **Duration:** ~20 min
- **Started:** 2026-07-18T01:12:09Z
- **Completed:** 2026-07-18T01:32:00Z
- **Tasks:** 2 completed
- **Files modified:** 2 (both in the GeniusSDK submodule)

## Accomplishments

- `GeniusSDK.h` gains `GeniusRegistrationMetadata` and `GeniusRegistrationDiscoveryEntry` structs, a new `GENIUS_NODE_ERROR_REGISTRATION` enum member, and 4 new exported function declarations
- `GeniusSDK.cpp` implements all 4 wrappers plus 3 anonymous-namespace helpers (`ToRegistrationMetadataProto`, `FromRegistrationMetadataProto`, `MakeGeniusAddress`)
- Only the 2-arg auto-derived-sequence `GeniusNode::RegisterChild` overload is exposed — the 3-arg manual-sequence overload remains internal-only, confirmed by a region-scoped grep
- Registration metadata string fields are converted via `strnlen`-bounded construction (T-02-01 threat mitigation), never via raw implicit `const char*` conversion

## Task Commits

Each task was committed atomically in the `GeniusSDK` submodule (branch `dev_childwallet`):

1. **Task 1: Add structs/enum/declarations to GeniusSDK.h** - `f50099c` (feat)
2. **Task 2: Implement wrapper functions in GeniusSDK.cpp** - `e262584` (feat)

**Plan metadata:** pending (docs commit, superproject)

_Note: Both commits live in the GeniusSDK submodule; the superproject's final docs commit bumps the submodule pointer._

## Files Created/Modified

- `GeniusSDK/src/GeniusSDK.h` - Adds `GeniusRegistrationMetadata`, `GeniusRegistrationDiscoveryEntry`, `GENIUS_NODE_ERROR_REGISTRATION`, and 4 new function declarations
- `GeniusSDK/src/GeniusSDK.cpp` - Implements the 4 wrapper functions plus 3 conversion helpers in the anonymous namespace

## Decisions Made

- `GENIUS_SDK_MAX_METADATA_STRING_SIZE` sized at 128, distinct from `GENIUS_SDK_ADDRESS_SIZE`, since game_id/publisher_id/dev_wallet are opaque caller strings with no address-shaped format enforced downstream
- `GeniusSDKGetRegistrationsForMain` treats zero discovered registrations as `GENIUS_NODE_RET_OK` with `*out_count = 0` (a valid empty result), reserving `GENIUS_NODE_ERROR_REGISTRATION` for genuine query failures
- Metadata proto round-trip uses `strnlen`-bounded `std::string` construction on the way in (`ToRegistrationMetadataProto`) and bounded `strncpy` on the way out (`FromRegistrationMetadataProto`), consistent with the existing `GeniusSDKGetBalanceGNUS` bounded-copy pattern

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Re-ran SuperGenius INSTALL target to resync stale installed headers**
- **Found during:** Task 2 build verification
- **Issue:** `GeniusNode.hpp`'s installed copy referenced `account/PublicChainInputValidator.hpp`, which was missing from the installed SuperGenius header tree (stale install predating that header's addition)
- **Fix:** Ran `cmake --build . --target INSTALL --config Release` in `SuperGenius/build/Windows/Release` to resync the installed header tree from source
- **Files modified:** None (build-artifact resync only, no source changes)
- **Verification:** `find .../include/account/PublicChainInputValidator.hpp` confirmed present after resync
- **Committed in:** N/A (build-directory artifact, not tracked in git)

---

**Total deviations:** 1 auto-fixed (1 blocking, build-environment resync — no source code changes)
**Impact on plan:** No impact on GeniusSDK.h/.cpp source correctness. Enabled partial progress on build verification before hitting the pre-existing blocker documented below.

## Issues Encountered

**GeniusSDK static-lib build verification blocked by a pre-existing SuperGenius/evmrelay CMake packaging gap — not caused by this plan's changes.**

After resyncing headers (see deviation above), the build still failed:

```
account/BridgeRelayer.hpp(19,10): error C1083: Cannot open include file: 'eth/eth_watch_service.hpp'
```

Root cause traced (not fixed, out of scope): `SuperGenius/evmrelay/src/CMakeLists.txt` exports the
`evmrelay` target to its own separate CMake package (`evmrelayConfig.cmake`) with
`$<INSTALL_INTERFACE:include/evmrelay>` as its public include directory.
`genius_node` links `evmrelay` `PUBLIC`, and the public header `GeniusNode.hpp`
transitively requires `account/BridgeRelayer.hpp` → `eth/eth_watch_service.hpp`.
`SuperGenius/cmake/config.cmake.in` (behind `SuperGeniusConfig.cmake`) never
`find_dependency(evmrelay)`s or includes `evmrelayTargets.cmake`, so external
consumers like `GeniusSDK` (via `find_package(SuperGenius)`) get an imported
`sgns::genius_node` target whose transitive `evmrelay` include path never resolves.
A temporary, uncommitted `-DCMAKE_CXX_FLAGS="/I ..."` workaround confirmed this
diagnosis but surfaced a further unrelated pre-existing Boost::coroutine/MSVC
template-instantiation error, so the workaround was reverted rather than pursued.

This is a pre-existing SuperGenius/evmrelay CMake packaging bug, unrelated to the two
files this plan is scoped to modify (`GeniusSDK.h`/`GeniusSDK.cpp`). Fully documented
in `deferred-items.md` in this phase directory, including the candidate fix
(add `find_dependency(evmrelay)` + `include(evmrelayTargets.cmake)` to
`SuperGenius/cmake/config.cmake.in`) for a future phase/plan.

**Verification performed in lieu of a full build:** all 4 new wrapper functions and 3
helpers were manually cross-checked line-by-line against the exact signatures in
`SuperGenius/src/account/GeniusNode.hpp`, `TransactionManager.hpp`
(`RegistrationDiscoveryEntry` fields), and `SGTransaction.proto`
(`RegistrationMetadata` fields). All grep-based structural acceptance criteria from
the plan pass (see Task Commits above and per-task verify blocks in `02-01-PLAN.md`).

## Known Stubs

None — all 4 functions are fully wired to the underlying `GeniusNode` calls, no
placeholder/mock data paths.

## Threat Flags

None — this plan's only new surface (registration metadata fixed-size buffers,
malloc'd discovery array) is exactly what `02-01-PLAN.md`'s `<threat_model>` already
covers (T-02-01 through T-02-04), and the corresponding mitigations (strnlen-bounded
conversion for T-02-01) were applied as specified.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- The v2.2 milestone's full target feature set (registration, discovery, balance query
  via GeniusSDK C API) is now implemented in source
- **Blocker for full verification:** the pre-existing SuperGenius/evmrelay CMake
  packaging gap must be fixed (see `deferred-items.md`) before the GeniusSDK static-lib
  target — and any downstream consumer (GeniusWallet, external game SDKs) — can build
  successfully against current `SuperGenius` HEAD
- No dedicated GeniusSDK/test unit tests were added, per REQUIREMENTS.md Out of Scope
  and per the standing project convention (SuperGenius already covers the underlying
  GeniusNode/TransactionManager logic — see MEMORY.md)

---
*Phase: 02-geniussdk-child-wallet-interfaces*
*Completed: 2026-07-18*

## Build Verification Update (2026-07-20)

The evmrelay/Boost::coroutine CMake blocker described above and in `deferred-items.md` has
been fixed in `GeniusSDK/cmake/CommonBuildParameters.cmake` (commits `e2277ec`, `6ced449`).
A full `GeniusSDK` build has been run and confirmed green end-to-end. Coverage items D1–D3
above (`human_judgment: true`, previously verified only by manual signature inspection) are
now also build-confirmed.

## Self-Check: PASSED

- FOUND: GeniusSDK/src/GeniusSDK.h
- FOUND: GeniusSDK/src/GeniusSDK.cpp
- FOUND: .planning/phases/02-geniussdk-child-wallet-interfaces/02-01-SUMMARY.md
- FOUND: f50099c (GeniusSDK submodule, Task 1 commit)
- FOUND: e262584 (GeniusSDK submodule, Task 2 commit)
