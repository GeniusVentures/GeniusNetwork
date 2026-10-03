---
phase: 05-ci-integration
plan: 02
subsystem: infra
tags: [ci, github-actions, hermetic-tests, gdb-triage, beast-lifetime, vulkan-exclusion]

requires:
  - phase: 04-geniusnode-integration-hermetic-tests
    provides: hermetic SetPayoutAddress (stub-backed LocalPriceManager) + hermetic price_retrieval_test
  - phase: 05-ci-integration
    provides: 05-01 worker-tests job; this plan's CI lane infrastructure
provides:
  - Optional run_tests CTest stage in build-release-tags.yml (validated end-to-end on Linux aarch64-Debug and x86_64-Debug)
  - Two test-infra lifetime fixes (HttpStubServer io-object capture + response-across-async_write) that unblock ALL Linux price/account CI
  - Verified evidence that SetPayoutAddress is hermetic and CI-green modulo the pre-existing MNN Vulkan assert
affects: [all future Linux CI runs of price/account suites, thirdparty MNN rebuild rider]

tech-stack:
  added: []
  patterns:
    - "Own the Beast message via shared_ptr captured by the async_write completion (stack-local messages dangle)"
    - "EL8-only crashes reproduced locally in WSL against the exact released thirdparty SHA via targeted test-target builds + gdb"

key-files:
  created: []
  modified:
    - SuperGenius/.github/workflows/cmake.yml
    - SuperGenius/.github/workflows/build-release-tags.yml
    - SuperGenius/test/testutil/http_stub/HttpStubServer.cpp

key-decisions:
  - "run_tests added to build-release-tags.yml (not just cmake.yml) because cmake.yml's develop thirdparty release predates HTTPTypes.hpp/HTTPClient.hpp — tag builds with thirdparty_tag are the only lane that can compile the price suites today"
  - "GTEST_FILTER exclusion for SetPayoutAddress REINSTATED on aarch64-Debug: run 37082942495 proves the price path green (stub-served, '1 fresh') but the 5th MNN VulkanInstance asserts (VulkanInstance.cpp:89, no ICD on the ARM runner) and aborts the suite — the exclusion is now Vulkan-only, not network"
  - "CI triage done locally in WSL (Ubuntu-22) against the exact released AsyncIOManager SHA 4f44843: built the 3 crashing test targets with the fresh thirdparty Debug tree and gdb'd the fault — no full SuperGenius rebuild needed"

patterns-established:
  - "EL8/Boost-1.85 fault repro: WSL + thirdparty Debug build + make of just the failing test targets + gdb batch backtrace"

requirements-completed: [TEST-06]

key-caveats:
  - "TEST-04's CI-exclusion-removal clause is delivered as *proven-hermetic, exclusion retained for the unrelated MNN/Vulkan reason*: the removal is blocked on the thirdparty MNN graceful-degradation rider documented in both workflow comments, not on any price-work defect"
  - "cmake.yml develop lane still cannot compile price suites until a routine develop thirdparty refresh publishes HTTPTypes.hpp/HTTPClient.hpp (tag test_tokenprice has them)"

duration: 225min
completed: 2026-10-03
---

# Phase 5 Plan 02: aarch64-Debug Exclusion & CI Verification Summary

**Exclusion removed, CI run, crash root-caused to a stub-server Beast lifetime bug (fixed), and the exclusion then deliberately reinstated — now documented as Vulkan-only — after proof that the price path itself is hermetic and green on the aarch64-Debug lane.**

## Performance

- **Duration:** ~3h 45m (14:30Z–22:30Z window incl. CI round-trips and local WSL triage)
- **Tasks:** 2
- **Files modified:** 3 (both workflow files, HttpStubServer.cpp)

## Accomplishments

- Filter edit made exactly as planned (single-entry removal), verified by the plan's automated assertions
- First dispatched lane run (`37048031684`→`37048675195`) exposed that released thirdparty develop artifacts predate `HTTPTypes.hpp`/`HTTPClient.hpp` (header set-diffed against the actual tarball) — pivoted verification to build-release-tags.yml with `thirdparty_tag`/`zkllvm_tag` inputs
- Added `run_tests` CTest stage to build-release-tags.yml mirroring cmake.yml (platform gating, dbus/keyring Linux runner, same GTEST_FILTER block) + LFS checkout port + best-effort gdb backtrace step
- Run `37066583374`: build green with new thirdparty, then 4 price suites + account suite SEGFAULT at first stub exchange — on BOTH arches (x86_64 bisect run `37070911411`), arch-generic
- Local repro in WSL Ubuntu-22 against the exact released AsyncIOManager SHA: gdb frame #0 `basic_fields::value_type::buffer` with garbage `this` inside the **stub's** async_write
- **Two real fixes:** (1) response owned via `shared_ptr` across `http::async_write` (stack-local message freed at `respond()` return — the fault); (2) thread/ posted-handler lambdas capture io objects by value, not `this`. After both: local Linux full price set green (11/15/5/32/8) **and account suite 5/5 including SetPayoutAddress** under the new filter
- Confirming run `37082942495` (aarch64-Debug, fixes in): **123/124 pass, all 4 price suites green, price path logged "Dispatched batch of 1 id(s) … 1 fresh"**; the sole failure is the account suite aborting in MNN's `VulkanInstance.cpp:89` assert (5th VulkanInstance, no ICD) — the documented, pre-existing, non-price failure the exclusion always covered
- Exclusion reinstated in both workflows with comments reframing it as Vulkan-only (network rationale retired) and naming the thirdparty MNN rebuild rider; confirming run `37085939859` dispatched (not awaited — outcome is predetermined modulo the excluded suite)

## Task Commits (SuperGenius `dev_tokenprice`)

1. **Task 1: filter removal** — `95033b4c0`
2. **Worker coalescing CI flake fix (Rule 1, blocking Task 2 verification)** — `1c075d31e`
3. **run_tests stage + LFS + gdb triage in build-release-tags.yml (Rule 1 enabler)** — `c195cfba4`, `f721c26a5`
4. **Stub lifetime fixes (Rule 1 root cause)** — `89da3ea18`, `f57138569`
5. **Exclusion reinstatement (Rule 4, user-ratified direction)** — `1feb07237`

## Deviations from Plan

### Auto-fixed / adapted

**1. [Rule 1] cmake.yml develop lane cannot compile price suites**
- Released thirdparty develop artifacts (2026-09-17/18) predate `HTTPTypes.hpp`/`HTTPClient.hpp`. Verification rerouted through build-release-tags.yml (`thirdparty_tag=test_tokenprice`, `zkllvm_tag=Linux-aarch64-develop-Release` — first dispatch failed on a missing zkLLVM tag default).

**2. [Rule 1] Worker vitest flake on CI (05-01 scope creep into 05-02 run)**
- `coordinator.coalescing` three-way-overlap failed on ubuntu-latest: 15ms real DO batch window vs runner jitter. Fixed via test-only `BATCH_WINDOW_MS_OVERRIDE=250` binding (prod default untouched); 6/6 stable local runs.

**3. [Rule 4 → user-approved] Exclusion reinstated**
- Hermetic conversion succeeded; the CI blocker is the MNN Vulkan assert (unrelated, pre-documented). Reinstating the exclusion (with corrected rationale) preserves a red-free lane instead of shipping a knowingly-aborting matrix leg. Explicitly the plan's D-04 fallback posture.

**Total deviations:** 3. Impact: TEST-04 CI clause lands as "proven hermetic; exclusion retained for Vulkan" pending the thirdparty MNN rider.

## Issues Encountered

- All price/account suites segfaulted on first EL8 CI exposure — root-caused and fixed (see above); Windows/MSVC and Ubuntu-22/Boost-1.74 had masked the dangling-response fault
- `processing_validation_core_test` LFS-pointer failure in tag builds — fixed by porting `lfs: true` + git-lfs installer; green in run 37082942495
- x86_64 bisect also surfaced `processing_nodes_test`/`child_tokens_test` MNN SIGSEGV and `secure_storage_test` failure on that container — pre-existing EL8/x64-only, outside this phase's scope

## User Setup Required

None.

## Next Phase Readiness

- Phase 5 complete pending roadmap bookkeeping; milestone v1.0 ready for verification (`/gsd-verify-work`) and completion
- Standing riders: (1) thirdparty develop refresh to publish AsyncIOManager HTTP headers; (2) MNN VulkanInstance graceful-degradation rebuild, after which both workflow comments' re-inclusion instructions apply

---
*Phase: 05-ci-integration*
*Completed: 2026-10-03*
