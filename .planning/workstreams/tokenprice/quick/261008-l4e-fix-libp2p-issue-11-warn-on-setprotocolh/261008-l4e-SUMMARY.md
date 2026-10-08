---
phase: 261008-l4e
plan: 01
subsystem: libp2p (thirdparty vendored)
tags: [libp2p, router, logging, diagnostics, quick-task]
requires:
  - "thirdparty/libp2p build tree with router_test target (pre-configured)"
provides:
  - "Warning log on setProtocolHandler handler overwrite naming the protocol ID (issue #11 option 1)"
  - "RouterTest.SetHandlerOverwrite regression test locking in overwrite routing semantics"
affects:
  - "Anything re-registering protocol handlers on a shared RouterImpl (e.g. second graphsync::Network) now logs warnings — output-only, zero behavior change"
tech-stack:
  added: []
  patterns:
    - "log::Logger member + fmt-brace warn in existence-check branch (matches autonat.hpp pattern)"
key-files:
  created: []
  modified:
    - thirdparty/libp2p/include/libp2p/network/impl/router_impl.hpp
    - thirdparty/libp2p/src/network/impl/router_impl.cpp
    - thirdparty/libp2p/test/libp2p/network/router_test.cpp
    - thirdparty (gitlink only)
decisions:
  - "Issue #11 option 1: warn-only on overwrite, keep replace semantics unchanged"
  - "router_test.cpp gains its own main() calling testutil::prepareLoggers() (INFO) because RouterImpl now owns a logger and gtest_main does not initialize libp2p logging"
metrics:
  duration: 10m
  completed: 2026-10-08
status: complete
actuals:
  tokens: 12000   # ~48KB diff+context chars/4
  tasks: 2
  commits: 2
  libp2p_head: 28f6a629389019c70ef8f06facb387384c8b9088
  thirdparty_head: 1cbf85a9e982b35aad5e1c983d182cb7e33c26e3
---

# Quick Task 261008-l4e: Fix libp2p issue #11 — warn on setProtocolHandler overwrite

`RouterImpl::setProtocolHandler` now logs `Router: overwriting existing handler for protocol [<id>]` (level WARN) when the protocol ID already has a handler, making silent handler clobbering visible (e.g. a second `graphsync::Network` stealing inbound traffic). Overwrite semantics are byte-for-byte unchanged; a new regression test locks them in. libp2p pointer bumped inside thirdparty.

## Commits

| Repo | Branch | Commit | Subject |
|------|--------|--------|---------|
| thirdparty/libp2p | master | `28f6a62` | fix(network): warn on setProtocolHandler overwrite (#11) |
| thirdparty | develop | `1cbf85a` | chore: bump libp2p — warn on setProtocolHandler overwrite (#11) |

No commits in the GeniusNetwork root (per plan; orchestrator handles root pointer bump + docs).

## What Changed

- `include/libp2p/network/impl/router_impl.hpp` — added `#include <libp2p/log/logger.hpp>` and private member `log::Logger log_ = log::createLogger("Router");` (style matches `autonat.hpp`).
- `src/network/impl/router_impl.cpp` — in `setProtocolHandler`'s loop, before assignment: `if (proto_handlers_.find(protocol) != proto_handlers_.end()) log_->warn(...)`; assignment line unchanged.
- `test/libp2p/network/router_test.cpp` — new `TEST_F(RouterTest, SetHandlerOverwrite)` (@given/@when/@then style): handler A registered, handler B re-registers same protocol, `handle()` routes to B (not A), `getSupportedProtocols()` contains exactly one entry. Plus a `main()` calling `testutil::prepareLoggers()`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] router_test crashed: "Logging system is not ready" assertion**
- **Found during:** Task 1 verify (test run after adding the logger member)
- **Issue:** `log::createLogger` asserts unless `setLoggingSystem()` ran first; `router_test` used default `gtest_main` which does not initialize libp2p logging. First run aborted with exit code 3 at `logger.cpp:20`.
- **Fix:** Added a custom `main()` to `router_test.cpp` (exact pattern from `connection_manager_test.cpp`): `testutil::prepareLoggers(soralog::Level::INFO)` (TRACE if `TRACE_DEBUG` env set) before `RUN_ALL_TESTS()`. INFO level chosen so overwrite warnings are visible in default test output, proving the fix.
- **Files modified:** thirdparty/libp2p/test/libp2p/network/router_test.cpp
- **Commit:** 28f6a62

Note on `addtest`: it links `GTest::main`, but this project's GTest provider does not force `gtest_main` on executables that define their own `main` — `connection_manager_test.cpp` (same `addtest` macro) already defines `main()`. Build linked cleanly; no duplicate-symbol error.

## Verification Results

- `cmake --build thirdparty/libp2p/build --target router_test --config Debug` → BUILD OK (twice: pre-change RED run, post-change GREEN run).
- `thirdparty/libp2p/build/test_bin/Debug/router_test.exe` → **8/8 tests PASSED, exit 0**, including new `SetHandlerOverwrite`. Warnings observed in output naming the protocol (`overwriting existing handler for protocol [/ping/1.5.2]`) — emitted only on re-registration, never on first registration (e.g. `SetHandlerPerfect` logs nothing).
- Chain integrity: `git -C thirdparty/libp2p rev-parse HEAD` == `git -C thirdparty rev-parse HEAD:libp2p` == `28f6a629389019c70ef8f06facb387384c8b9088`.
- Collateral staging: none — thirdparty `develop` commit `1cbf85a` diff is the `libp2p` gitlink only; MNN/fmt/gnus_upnp modifications remain unstaged; untracked `.planning/research/.cache/` and `Testing/` untouched. Residual ` M libp2p` in thirdparty status is untracked-content dirt only (`git diff libp2p` is empty; gitlink SHAs match exactly).

## Known Stubs

None.

## Self-Check: PASSED

- FOUND: thirdparty/libp2p/include/libp2p/network/impl/router_impl.hpp (commit 28f6a62)
- FOUND: thirdparty/libp2p/src/network/impl/router_impl.cpp (commit 28f6a62)
- FOUND: thirdparty/libp2p/test/libp2p/network/router_test.cpp (commit 28f6a62)
- FOUND: thirdparty gitlink commit 1cbf85a recording libp2p @ 28f6a62
