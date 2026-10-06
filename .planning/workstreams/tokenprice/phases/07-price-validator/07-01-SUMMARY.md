---
phase: 07-price-validator
plan: 01
subsystem: coinprices
tags: [cpp17, gtest, price-validation, tolerance-band, cost-binding, hermetic-tests, cmake]

requires:
  - phase: 06-price-claim-wire-format-history
    provides: Task.claimed_price double on the wire, LocalPriceManager history with QueryHistory->PriceHistoryStats, escrow DAG timestamp as reference time
provides:
  - Pure ValidatePrice(PriceValidationInput, PriceValidatorConfig) -> PriceValidationResult with 8-value typed reason taxonomy (VAL-01)
  - Shared ObservationWindow formula PriceObservationWindow(T, config) = [T-(ttl+skew), T+skew] for the Phase 8 caller's QueryHistory bounds (D-07-02)
  - ResolvePriceValidatorConfig() + four SGNS_PRICEVAL_* env knobs with validated fallback (VAL-02)
  - ShouldTriggerRefetch(reason) NO_COVERAGE self-heal policy hook for the Phase 8 caller (D-07-06)
  - price_validator_test hermetic gtest suite (22 tests, zero mocks) wired beside the price_* family
affects: [08-consensus-wiring, phase-8-validator-hook, price telemetry/logging]

actuals:
  tokens: 8743   # chars/4 over the realized submodule diff (34,970 chars, 814 insertions)
  tasks: 3
  commits: 5     # MEASURED: git rev-list --count 9fcdabf5..HEAD in the SuperGenius submodule

tech-stack:
  added: []      # in-repo building blocks only (GTest, Boost, CMake already present)
  patterns:
    - "Pure free-function decision core with typed-enum + diagnostics struct return (D-07-10) beside PriceFreshness.hpp's ClassifyFreshness"
    - "Header-only getenv knob resolution with validated fallback and NO function-local static (PriceEndpoints.hpp shape, Pitfall 6)"
    - "kEpochBase fixed-epoch hermetic gtest suite with zero mocks and zero system_clock::now()"
    - "Static-archive pull semantics for cross-library symbol resolution (no coinprices->genius_node link, Pitfall 5)"

key-files:
  created:
    - SuperGenius/src/coinprices/PriceValidator.hpp
    - SuperGenius/src/coinprices/PriceValidator.cpp
    - SuperGenius/test/src/price_validator/CMakeLists.txt
    - SuperGenius/test/src/price_validator/price_validator_test.cpp
  modified:
    - SuperGenius/src/coinprices/CMakeLists.txt
    - SuperGenius/test/src/CMakeLists.txt

key-decisions:
  - "Task 0 auto-selected reject-fail-closed per the checkpoint's auto_select attribute (orchestrator-authorized); matches locked D-07-08/D-07-09 - no conflict"
  - "Diagnostics (band, echoed stats, window bounds) computed from stats+config only and echoed on every reject path, not just the band stage - Phase 8 logs complete context without re-derivation (Pitfall 7)"
  - "Reused existing test/testutil/scoped_env.hpp (ScopedEnvVar) for RAII env guards instead of writing a new guard - it implements exactly the _putenv/setenv semantics Task 3 prescribed"

patterns-established:
  - "Fail-fast reason chain with exactly one typed reason per input in locked order (D-07-11): legacy -> timestamp -> cost binding -> coverage -> band"
  - "Cost binding = exact integer equality with the CalculateCostMinions oracle, guarded by isfinite/negative checks BEFORE the oracle (Pitfall 1 / T-07-01)"

requirements-completed: [VAL-01, VAL-02, VAL-03, VAL-04, TEST-01]

coverage:
  - id: D1
    description: "Pure ValidatePrice decision core: D-07-11 fail-fast chain with all 8 typed reasons, inclusive boundaries at band edges / skew edge / max-age edge, and exact-integer cost binding"
    requirement: VAL-01
    verification:
      - kind: unit
        ref: "SuperGenius/test/src/price_validator/price_validator_test.cpp#PriceValidator.InBandAccepted (+16 more PriceValidator.* cases)"
        status: pass
    human_judgment: false
  - id: D2
    description: "SGNS_PRICEVAL_* env resolver with validated fallback semantics plus ShouldTriggerRefetch NO_COVERAGE self-heal hook"
    requirement: VAL-02
    verification:
      - kind: unit
        ref: "SuperGenius/test/src/price_validator/price_validator_test.cpp#PriceValidatorConfig.ResolverDefaults/ResolverOverrides/ResolverNonsenseFallsBack/ResolverNotCached/RefetchOnlyOnNoCoverage"
        status: pass
    human_judgment: false
  - id: D3
    description: "Hermetic price_validator_test target (zero mocks, zero system_clock::now) wired into the price_* ctest family with no link regression to price_manager_test"
    requirement: TEST-01
    verification:
      - kind: unit
        ref: "ctest --test-dir SuperGenius/build/Windows/Release -C Release -R price_ -> 6/6 passed"
        status: pass
    human_judgment: false

duration: 16min
completed: 2026-10-06
status: complete
---

# Phase 7 Plan 01: Price Validator Summary

**Pure ValidatePrice fail-fast chain (legacy → timestamp → cost binding → coverage → band) with an 8-value typed reason taxonomy, SGNS_PRICEVAL_* env config, NO_COVERAGE self-heal hook, and a 22-test hermetic gtest suite — all green, zero mocks.**

## Performance

- **Duration:** ~16 min
- **Started:** 2026-10-06T20:15:14Z
- **Completed:** 2026-10-06T20:31:00Z
- **Tasks:** 3 execution tasks + 1 auto-selected decision checkpoint
- **Files modified:** 6 (4 created, 2 modified — all in the SuperGenius submodule)

## Accomplishments

- `ValidatePrice` decision core in `src/coinprices/PriceValidator.{hpp,cpp}`: exactly one typed reason per input in the locked D-07-11 order, NaN/±inf/negative prices rejected deterministically BEFORE the cost oracle (T-07-01), cost binding by exact integer equality with `TokenAmount::CalculateCostMinions` (T-07-03), coverage keyed on `stats.count` never `min` (T-07-02/Pitfall 2), fail-closed `LegacyNoPrice` on `claimed_price == 0.0` including −0.0 (D-07-08, Task 0 confirmed).
- `ResolvePriceValidatorConfig()` with four documented `SGNS_PRICEVAL_*` knobs: tolerance double validated to `[0.0, 1.0)`, seconds validated finite/integral/`> 0`; every nonsense input (empty, "abc", "-5", "nan", "1.5", "0") falls back to that knob's default — never a non-finite or degenerate config (VAL-02, T-07-07). `ShouldTriggerRefetch` true only for `NoCoverage` (D-07-06).
- Shared `PriceObservationWindow(T, config)` formula (`from = T − (ttl + skew)`, `to = T + skew`) so the Phase 8 caller and validator can never drift (D-07-02, Pitfall 3).
- `price_validator_test` (22 tests, zero mocks, zero `system_clock::now`) wired with `coinprices + genius_node_test + Boost::headers`; `price_manager_test` and the whole `price_` ctest set show no link regression (6/6 passed).

## Task Commits

All in the `SuperGenius` submodule on `dev_price_validation` (base `9fcdabf5a`):

1. **Task 1 RED** — `1b8a94cba` test(07-01): add failing InBandAccepted test for ValidatePrice (header contract + compile/link stub + build wiring; RED_EVIDENCE_OK)
2. **Task 1 GREEN** — `d2aba895c` feat(07-01): implement ValidatePrice fail-fast chain
3. **Task 2** — `be7b6c91f` test(07-01): expand verdict matrix with exact-boundary tests (17/17 green)
4. **Task 3 RED** — `c6cf033e7` test(07-01): add failing SGNS_PRICEVAL_* resolver + refetch-hook tests (RED_EVIDENCE_OK)
5. **Task 3 GREEN** — `600de1e66` feat(07-01): implement SGNS_PRICEVAL_* resolver + ShouldTriggerRefetch (22/22 green, ctest 6/6)

## Files Created/Modified

- `SuperGenius/src/coinprices/PriceValidator.hpp` — public contract: 8-value `PriceValidationReason`, `inline constexpr` defaults (windowTtl reuses `kStaleMaxAge` — no restated 300 literal in code), `PriceValidatorConfig/Input/Result`, `ObservationWindow` + window helper, `ValidatePrice` decl, env resolver + refetch hook
- `SuperGenius/src/coinprices/PriceValidator.cpp` — the pure fail-fast chain implementation
- `SuperGenius/test/src/price_validator/price_validator_test.cpp` — hermetic TEST-01 suite (17 `PriceValidator.*` + 5 `PriceValidatorConfig.*`)
- `SuperGenius/test/src/price_validator/CMakeLists.txt` — new `price_validator_test` target
- `SuperGenius/src/coinprices/CMakeLists.txt` — `PriceValidator.cpp` appended to `coinprices` (no `genius_node*` link declared — Pitfall 5)
- `SuperGenius/test/src/CMakeLists.txt` — suite registered beside `price_manager`

## Decisions Made

- Task 0 checkpoint auto-selected `reject-fail-closed` per its `auto_select` attribute (orchestrator-authorized in the dispatch objective); it matches the locked CONTEXT decision D-07-08/D-07-09 — recorded, no escalation needed.
- Diagnostics are echoed on every reject path (computed from stats + config only), not just at the band stage — richer Phase 8 logging, still deterministic, still claimed-price-independent.
- Reused the existing `sgns::testutil::ScopedEnvVar` (test/testutil/scoped_env.hpp) for env-guard RAII instead of authoring a new guard — it implements exactly the `_putenv`/`setenv` CRT-family semantics the plan prescribed (see Deviations).

## Deviations from Plan

### Auto-fixed Issues

**1. [Reuse of existing asset] ScopedEnvVar instead of a new RAII env guard (Task 3)**
- **Found during:** Task 3 test authoring
- **Issue:** Plan said to write "a small RAII guard ... using _putenv under _WIN32 and setenv/unsetenv otherwise"; the repo already ships `test/testutil/scoped_env.hpp` with exactly those semantics (Phase 4, verified used by account_management_test).
- **Fix:** Reused `ScopedEnvVar` rather than duplicating a second guard — same CRT family, same restore semantics, less new surface.
- **Files modified:** test/src/price_validator/price_validator_test.cpp (include only)
- **Verification:** ResolverOverrides/ResolverNotCached/RefetchOnlyOnNoCoverage green; env restored between tests
- **Committed in:** `c6cf033e7`

---

**Total deviations:** 1 (reuse-substitution; no scope creep, no rule-1..3 bug fixes were needed — the Task 1 chain survived the full Task 2 boundary matrix unchanged)
**Impact on plan:** None — plan's verify/acceptance criteria all met as written.

## TDD Gate Compliance

- **Task 1:** RED `1b8a94cba` → `check tdd-red-evidence` verdict `RED_EVIDENCE_OK` (target `PriceValidator#InBandAccepted` failed on the accepted/band assertions against the compile/link stub, exit 1) → GREEN `d2aba895c` (1/1 passed).
- **Task 3:** RED `c6cf033e7` → `RED_EVIDENCE_OK` (target `PriceValidatorConfig#ResolverOverrides` failed against the defaults-only stub, plus ResolverNotCached/RefetchOnlyOnNoCoverage, exit 1) → GREEN `600de1e66` (22/22 passed).
- **Task 2:** matrix tests were green on arrival against the Task 1 GREEN chain — no RED was possible because the plan deliberately front-loads the full chain in the tracer and uses Task 2 purely as verification expansion (its own action reads "fix PriceValidator.cpp **if** a matrix case exposes a boundary or ordering bug" — none did). Recorded here per the fail-fast rule-1 investigation outcome rather than fabricating an artificial failure.
- Git gate greps confirm `test(07-01):` × 3 and `feat(07-01):` × 2 commits in the plan range.

## Issues Encountered

- `tdd-red-evidence` record authoring on Windows PowerShell: `ConvertTo-Json` (PS 5.1) HTML-escapes `<` as `\u003c` and serializes `Get-Content` strings as `{value, ReadCount}` objects, both of which initially classified as INVALID_RED (`zero_tests_discovered`). Fixed by building the record JSON manually (`[IO.File]::ReadAllText` + explicit JSON string escaping). Both records then validated `RED_EVIDENCE_OK`. No production-code impact.
- Pre-existing benign `LNK4199` (/DELAYLOAD ignored) linker warnings on the test target — not introduced by this plan; out of scope.

## User Setup Required

None — no external service configuration. `SGNS_PRICEVAL_*` env vars are optional operator overrides with safe defaults.

## Next Phase Readiness

- The full validator API (`ValidatePrice`, `PriceObservationWindow`, `ResolvePriceValidatorConfig`, `ShouldTriggerRefetch`) is ready for the Phase 8 receive-path hook: caller fetches escrow via `TransactionManager::FetchTransaction`, derives `blockSize`, queries `LocalPriceManager::QueryHistory` over `PriceObservationWindow` bounds, and calls `ValidatePrice` with injected `now`.
- No blockers. Window formula, reason taxonomy, and check order are locked and test-proven; determinism prerequisites (purity, shared formula) hold.

## Self-Check: PASSED

All 5 created/modified deliverable files exist on disk; all 5 task commits (`1b8a94cba`, `d2aba895c`, `be7b6c91f`, `c6cf033e7`, `600de1e66`) verified in the submodule log. Commit count (5) matches the measured `git rev-list --count 9fcdabf5..HEAD`.

---
*Phase: 07-price-validator*
*Completed: 2026-10-06*
