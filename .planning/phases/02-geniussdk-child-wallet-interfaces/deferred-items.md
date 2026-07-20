# Deferred Items — Phase 2 (GeniusSDK Child Wallet Interfaces)

## GeniusSDK static-lib build cannot be verified end-to-end (pre-existing, out of scope) — RESOLVED 2026-07-20

**Resolution:** Fixed directly in `GeniusSDK/cmake/CommonBuildParameters.cmake` rather than in
`SuperGenius/cmake/config.cmake.in` (the candidate fix location below). Two commits:

- `e2277ec` — adds `set(evmrelay_DIR ...)` + `find_package(evmrelay CONFIG REQUIRED)` directly in
  `CommonBuildParameters.cmake`, before `find_package(SuperGenius)`. This makes `evmrelay`'s
  `include/evmrelay` usage-requirement available in the consumer's build tree independently of
  whether `SuperGeniusConfig.cmake` declares the transitive dependency, resolving the
  `eth/eth_watch_service.hpp` include failure.
- `6ced449` ("Exception handling flag") — adds `coroutine` to the `find_package(Boost CONFIG
  REQUIRED COMPONENTS ...)` list, resolving the secondary Boost::coroutine/MSVC
  template-instantiation error (`'current_exception': identifier not found`) surfaced once past
  the evmrelay include issue.

A full `GeniusSDK` build has been run and confirmed green end-to-end. The three deferred
verification items in `02-01-SUMMARY.md` (D1–D3, previously `human_judgment: true` pending build
confirmation) are now build-confirmed, not just inspection-confirmed.

---

## Original issue (superseded by resolution above)

**Found during:** Phase 2 Plan 01, Task 2 build verification step.

**Symptom:** `cmake --build . --target GeniusSDK --config Release` fails to compile
`GeniusSDK.cpp` with:

```
account/GeniusNode.hpp(29,10): error C1083: Cannot open include file: 'account/PublicChainInputValidator.hpp'
```

and, after that is resolved by re-running the SuperGenius `INSTALL` target (header
install tree was stale):

```
account/BridgeRelayer.hpp(19,10): error C1083: Cannot open include file: 'eth/eth_watch_service.hpp'
```

**Root cause (traced, not fixed):** `SuperGenius/evmrelay/src/CMakeLists.txt` installs
the `evmrelay` target's public headers/usage-requirements to its own separate export
set (`install(EXPORT evmrelay ... NAMESPACE evmrelay::)`, `evmrelayConfig.cmake` at
`lib/cmake/evmrelay`), with `$<INSTALL_INTERFACE:include/evmrelay>` as its public
include directory. `genius_node` links `evmrelay` `PUBLIC` (see
`SuperGenius/src/account/CMakeLists.txt` `GENIUS_NODE_LIBS`), and `GeniusNode.hpp`
transitively requires `account/BridgeRelayer.hpp` → `eth/eth_watch_service.hpp` at the
public-header level. However, `SuperGenius/cmake/config.cmake.in` (the template behind
`SuperGeniusConfig.cmake`) only does
`include("${CMAKE_CURRENT_LIST_DIR}/supergeniusTargets.cmake")` — it never
`find_dependency(evmrelay)`s or includes `evmrelayTargets.cmake`. So external
consumers of `SuperGeniusConfig.cmake` (like `GeniusSDK`, via `find_package(SuperGenius)`
in `GeniusSDK/cmake/CommonBuildParameters.cmake`) get an imported `sgns::genius_node`
target whose `INTERFACE_LINK_LIBRARIES` references a bare `evmrelay` target name that
is never defined in the consumer's build tree — so the compiler never receives
`evmrelay`'s `include/evmrelay` search path, and any translation unit that transitively
includes `account/BridgeRelayer.hpp` (via `GeniusNode.hpp`) fails.

A quick manual `-DCMAKE_CXX_FLAGS="/I ..."` workaround (not committed, reverted)
confirmed this diagnosis but also surfaced a second, unrelated pre-existing issue once
past it: a Boost::coroutine / MSVC template-instantiation error
(`'current_exception': identifier not found` in
`boost/coroutine/detail/push_coroutine_object.hpp`), suggesting `/EHsc` or an
`<exception>` include ordering issue elsewhere in the dependency chain.

**Why deferred:** Both issues are pre-existing SuperGenius/evmrelay CMake packaging
gaps, entirely unrelated to the two files this plan is scoped to
(`GeniusSDK/src/GeniusSDK.h`, `GeniusSDK/src/GeniusSDK.cpp`). Fixing them requires
changes to `SuperGenius/cmake/config.cmake.in` (add `find_dependency(evmrelay)` /
include `evmrelayTargets.cmake`) and/or further Boost coroutine dependency
investigation — cross-repo build-system changes out of this plan's scope
(`files_modified` lists only the two GeniusSDK files) and per the deviation-rule scope
boundary ("only auto-fix issues directly caused by the current task's changes").

**Verification performed instead:** All four new GeniusSDK.cpp wrapper functions and
three helpers were manually cross-checked line-by-line against the exact signatures in
`SuperGenius/src/account/GeniusNode.hpp` (`RegisterChild` x2, `GetRegistrationsForMain`,
`GetChildBalance` x2), `SuperGenius/src/account/TransactionManager.hpp`
(`RegistrationDiscoveryEntry` field names/types), and
`SuperGenius/src/account/proto/SGTransaction.proto` (`RegistrationMetadata` field
names). All grep-based structural acceptance criteria for both tasks pass. The
2-arg auto-derive `RegisterChild` overload is called (never the 3-arg manual-sequence
overload) — confirmed via the "sequence" region-scoped grep returning 0 in the header
and via direct code inspection in the .cpp.

**Candidate fix (future phase/plan):** Add `find_dependency(evmrelay)` +
`include(evmrelayTargets.cmake)` to `SuperGenius/cmake/config.cmake.in`, then verify
the GeniusSDK static-lib build end-to-end; investigate the Boost::coroutine MSVC issue
separately if it persists once the include path is fixed at the CMake level.
