# Phase 18: Build Stability - Research

**Researched:** 2026-08-20
**Domain:** C++ concurrency (mutex re-entrancy), GoogleTest regression-test authoring, CTest timeout configuration — `SuperGenius/SGProcessingManager`
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Central finding — the described bug does not currently reproduce**
- **D-01:** Direct reproduction against current HEAD (fresh same-day Debug build, real NVIDIA GeForce RTX 4070 Ti SUPER present) shows none of the three named tests deadlock — confirmed via 4 separate runs (standalone `.exe` invocations and via `ctest -C Debug`, individually and as a set). `ProcessingDatatypesTest` (all subtests), `ProcessingDispatchTest` (12/12), and `vulkan_init_concurrency_test` all pass cleanly.
- **D-02:** Git history in the `SGProcessingManager` submodule shows commit `528a92a` ("Fix hang on OSX", 2026-08-06) already restructured `CapabilityValidator::BuildSnapshot()` (`src/capability/capability_validator.cpp`) to stop holding `VulkanInitMutex()` while calling `ensureVulkanDevice()` — which itself acquires the same mutex internally via `RenderProcessor::InitializeContext()`'s double-checked-locking pattern. This is exactly the self-deadlock pattern BUILD-01 and the pending todo describe. The fix predates both the todo's filing (2026-08-10) and Phase 18's creation (2026-08-17) — the todo was almost certainly filed against stale, not-yet-rebuilt test binaries, and the ROADMAP/REQUIREMENTS carried it forward as still-open without re-verification.
- **D-03 (closure bar):** Treat BUILD-01 as verify-and-close, not a new fix. Planning/execution should: (1) document this evidence trail (already-merged fix + clean repro) as the closure proof, mirroring Phase 13/19's honest-reporting convention; (2) add one regression test that explicitly pins this exact scenario — `ProcessingManager::Create()` with a real Vulkan device present must return without hanging or throwing — ideally timeout-guarded so a future regression fails fast in CI instead of hanging the suite; (3) do not modify `VulkanInitMutex`'s locking model itself (matches ROADMAP SC4, already locked).
- **D-04 (scope):** Keep all code/test changes inside `GeniusNetwork/SuperGenius`. Do not edit files in the separate `GeniusCognitiveSystem` repo as part of this phase — see Deferred Ideas for the cross-repo lead uncovered during this discussion.

**Flaky, unrelated observation — out of scope**
- **D-05:** During repro, one of four `ctest` runs of the three-test trio hit a flaky, non-reproducing failure: `processing_dispatch_test` failed with `Failed to open file (Windows): The system cannot find the file specified` (looks like a CWD-relative test-fixture path difference between running the `.exe` directly vs. via `ctest`), followed by an apparent stall before `vulkan_init_concurrency_test`'s result printed. Three subsequent runs (including the identical trio, and `processing_dispatch_test` isolated, and paired with `vulkan_init_concurrency_test`) all passed cleanly — it did not reproduce again. **User decision: out of scope, note only.** Do not investigate or fix in this phase.

### Claude's Discretion
- Evidence bar for closure: Windows-with-real-GPU (the only real-device host exercised in this discussion) is accepted as sufficient; no explicit ask for additional Linux/macOS re-verification was raised, and ROADMAP's SC1-3 don't specify a platform beyond "a real Vulkan device is present."
- Exact form/location of the new regression test (e.g., extending `vulkan_init_concurrency_test.cpp` vs. a new dedicated test) is left to planning/research.

### Deferred Ideas (OUT OF SCOPE)
- **Cross-repo NEO-SWARM stale skip-guard:** `GeniusCognitiveSystem/GNUS-NEO-SWARM/test/integration/test_sgprocessing_pipeline.cpp`'s `Fp4UltraFormat_DispatchesToTensorProcessor` and `LlmDataType_JobReachesRegisteredProcessor` tests skip whenever a real Vulkan device is present, specifically to dodge this bug (added 2026-08-18, per their own 04-VERIFICATION.md, as a *designed deferral* to this phase — not an independent fresh repro of a hang in that exact binary). Given D-01/D-02's finding, this guard is very likely stale now and could be removed so those two tests actually execute and pass on a real-device host. User decided this phase stays SuperGenius-only (D-04); flagging this as a strong, evidence-backed lead for a future todo/phase in the `GeniusCognitiveSystem`/`neoswarm` workstream to pick up and verify (their own build was separately reported as blocked by an unrelated `get_third_party_dir()` CMake configure issue in 04-VERIFICATION.md — that would need checking too before this lead can be closed out).
- **Flaky `processing_dispatch_test` CWD-relative file failure (D-05):** noted, not investigated. If it recurs, it looks like a test-fixture path resolution issue (differs between direct `.exe` invocation and `ctest`), unrelated to `VulkanInitMutex`.

**Reviewed Todos (not folded):** None — `todo.match-phase` returned zero matches for Phase 18 at discussion time.
</user_constraints>

## Summary

This phase is verify-and-close, not a new fix, and this research's job was to sanity-check CONTEXT.md's D-01/D-02 claims against current HEAD rather than re-derive them — all of them check out. Direct inspection of `SuperGenius/SGProcessingManager/src/capability/capability_validator.cpp:211-235`, `src/processingbase/ProcessingManager.cpp:426-513`, `src/processors/processing_processor_render.cpp:58-194`, and `src/processors/vulkan_gpu_probe.cpp` confirms the code is exactly as CONTEXT.md describes: `BuildSnapshot()` calls `ensureVulkanDevice()` *outside* `VulkanInitMutex()`'s lock (with an explicit comment at lines 220-226 explaining why holding the lock there would self-deadlock), and only re-acquires the lock afterward, briefly, to read device properties. `git merge-base --is-ancestor 528a92a HEAD` confirms `528a92a` ("Fix hang on OSX", 2026-08-06) is a genuine ancestor of current HEAD in the `SGProcessingManager` submodule, and it is the most recent commit touching `capability_validator.cpp` before an unrelated PassType-naming commit — so the fix is real, current, and not stale. `ctest --test-dir build/Windows/Debug -N` confirms all three named tests (`processing_datatypes_test`, `processing_dispatch_test`, `vulkan_init_concurrency_test`) are live, discoverable ctest targets today.

The one substantive open question this research resolves for planning is *how* to add the regression test D-03 calls for. `vulkan_init_concurrency_test.cpp` is confirmed as the right home: it already builds against `ProcessingBase` (which PUBLICly links `SGProcessors`, the library containing `vulkan_gpu_probe.cpp`/`HasUsableVulkanDevice()`), already includes `<processingbase/ProcessingManager.hpp>`, and already has the `SetUpTestSuite`/`LoadAndPatchJson` fixture scaffolding a new `TEST_F` can reuse verbatim. For "fail fast instead of hang," this codebase has exactly one established idiom — a CMake-level `set_tests_properties(<target> PROPERTIES TIMEOUT <seconds>)` applied per-ctest-target (precedent: `SuperGenius/test/src/bridge_race/CMakeLists.txt`) — not an in-test `std::future::wait_for` harness (that pattern exists once in the codebase, in production networking code, never inside a gtest case). The planner should follow the CMake TIMEOUT precedent rather than inventing a new in-test wait-with-timeout idiom.

**Primary recommendation:** Add one new `TEST_F(VulkanConcurrentInitTest, ...)` (or a small dedicated fixture in the same file) to `vulkan_init_concurrency_test.cpp` that calls `sgns::sgprocessing::ProcessingManager::Create()` on a minimal valid job JSON, gated by `HasUsableVulkanDevice()` (mirroring `capture_smoke_test.cpp`'s `GTEST_SKIP()` convention) so it degrades gracefully on GPU-less CI hosts, and asserts the call returns (no throw, no hang) via plain `EXPECT_TRUE(result.has_value())`/`EXPECT_NO_THROW`. Give the `vulkan_init_concurrency_test` CMake target an explicit `set_tests_properties(... PROPERTIES TIMEOUT 60)` (or similar) so a future regression produces a ctest-level timeout failure instead of hanging the suite. Do not touch `VulkanInitMutex()`, `BuildSnapshot()`, or `InitializeContext()` — CONTEXT.md D-03/D-04 forbid it, and this research found nothing suggesting those need to change.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Vulkan capability probing (`BuildSnapshot`/`ensureVulkanDevice`) | Backend / native library (`SGProcessingManager` C++ static libs) | — | Runs entirely in-process at `ProcessingManager::Create()`, no network/API boundary involved |
| Shared Vulkan init synchronization (`VulkanInitMutex`) | Backend / native library | — | Process-wide C++ primitive; not exposed to any client, SDK, or service boundary |
| Regression test coverage | Test / CI tier | Backend (exercises real backend code) | New test is a CTest target, but it directly drives production `ProcessingManager`/`RenderProcessor` code paths |
| Test-hang mitigation (CTest TIMEOUT) | CI / build tooling | — | Configured in CMake, enforced by the CTest runner, not application code |

This phase touches exactly one architectural tier (native backend + its test harness) — there is no browser, SSR, API, or CDN surface involved.

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| BUILD-01 | `ProcessingManager::Create()`'s Vulkan capability-probe no longer deadlocks `ProcessingDatatypesTest`/`ProcessingDispatchTest`/`vulkan_init_concurrency_test` when a real Vulkan device is present | Confirmed fix (`528a92a`) is present at HEAD and the three named CTest targets exist and are discoverable; this research supplies the exact file/pattern to add D-03's regression test and the CTest-native mechanism to make it fail fast rather than hang |

## Standard Stack

No new libraries are needed for this phase — it is a pure regression-test addition using infrastructure already vendored and wired into the build (GoogleTest, Boost.DLL, the project's own `ProcessingBase`/`SGProcessors` static libraries). No `npm`/`pip`/`cargo` installation step applies; this is a C++/CMake project.

### Core
| Component | Version | Purpose | Why Standard |
|-----------|---------|---------|---------------|
| GoogleTest (`GTest::gtest_main`) | Already vendored/linked via `addtest()` CMake macro | Test framework for the new regression case | Every test in `SuperGenius/test/` already uses it; `addtest()` wires it automatically |
| `HasUsableVulkanDevice()` (`vulkan_gpu_probe.cpp`, part of `SGProcessors`) | Existing, in-tree | Gate the new test so it `GTEST_SKIP()`s cleanly on hosts with no real Vulkan device | Already the established gating pattern (`capture_smoke_test.cpp`) — reuse, don't reinvent |
| `sgns::sgprocessing::ProcessingManager::Create()` | Existing, in-tree | The exact call path BUILD-01 requires to no longer deadlock | This is the function under test — D-03's regression scenario is literally "call this with a real device present and confirm it returns" |

### Supporting
No supporting/new libraries required.

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| CMake `set_tests_properties(... PROPERTIES TIMEOUT N)` | In-test `std::thread` + `std::future::wait_for(timeout)` harness | The in-test approach reports a clean gtest FAIL with a message instead of a ctest-level "Timeout" result, but it is unprecedented in this codebase's *test* code (only precedent is production code in `evmrelay/include/discv4/discovery.hpp:157`) and adds real complexity (a detached/leaked thread if the guarded call never returns, since std::thread can't be force-killed). The CMake TIMEOUT property is one line, matches existing precedent (`bridge_race` tests), and satisfies D-03's actual ask ("fails fast in CI instead of hanging the suite") without inventing new test infrastructure. |
| Extending `vulkan_init_concurrency_test.cpp` | Creating a brand-new test file/target | CONTEXT.md's own Reusable Assets section and this research's file inspection agree: the existing file already has the right includes, fixture, and JSON-patching helper a new `TEST_F` can reuse verbatim. A new file would duplicate `PatchJsonUrisToAbsolute`/`LoadAndPatchJson`/`SetUpTestSuite` for no benefit. |

**Installation:** None — no new packages. This phase adds test source lines to an existing target only.

## Package Legitimacy Audit

**Not applicable to this phase.** No new external packages (npm/PyPI/crates or otherwise) are introduced. The phase adds a regression test using already-vendored, already-linked in-tree code (GoogleTest via the existing `addtest()` CMake macro, and the project's own `ProcessingBase`/`SGProcessors` static libraries). `Package Legitimacy Audit` table intentionally omitted — nothing to audit.

## Architecture Patterns

### System Architecture Diagram

```
[ctest runner]
      |
      v
[vulkan_init_concurrency_test.exe]
      |
      |--(existing) RepeatedConcurrentInitNoRaceOrCrash
      |     -> spawns 3 threads -> ProcessingManager::Create() x2, RenderProcessor::StartProcessing() x1
      |        -> each reaches VulkanInitMutex() via its own call path
      |
      |--(NEW, D-03) <RegressionTestName>
            |
            v
      HasUsableVulkanDevice()  --false--> GTEST_SKIP() [host has no real GPU; expected, not a failure]
            |
           true
            v
      ProcessingManager::Create(minimalJobJson)
            |
            v
      Init() -> CapabilityValidator::BuildSnapshot(factories, mnnCount, ensureVulkanDeviceLambda)
            |
            |-- ensureVulkanDevice() called OUTSIDE VulkanInitMutex() lock (capability_validator.cpp:220-228)
            |     -> static RenderProcessor::InitializeContext()
            |          -> double-checked lock on VulkanInitMutex() (processing_processor_render.cpp:58-66)
            |          -> vk-bootstrap instance/device creation
            |
            |-- AFTER ensureVulkanDevice() returns: brief VulkanInitMutex() re-lock
            |     -> vkGetPhysicalDeviceProperties/MemoryProperties only (capability_validator.cpp:229-234)
            v
      BuildSnapshot returns -> Init() continues -> Create() returns outcome::result<shared_ptr<ProcessingManager>>
            |
            v
      EXPECT_TRUE(result.has_value()); EXPECT_NO_THROW(...)  [must return promptly -- no hang]
            |
            v
      [ctest TIMEOUT N on this target -- safety net if a future regression reintroduces the hang]
```

### Recommended Project Structure
No new files/directories. All changes land in:
```
SuperGenius/test/src/processing_vulkan_concurrency/
├── vulkan_init_concurrency_test.cpp   # add one new TEST_F here
└── CMakeLists.txt                     # add set_tests_properties(... TIMEOUT ...) here
```

### Pattern 1: GTEST_SKIP-gated real-device test
**What:** Probe for a usable Vulkan device with `HasUsableVulkanDevice()` before running GPU-dependent assertions; `GTEST_SKIP()` (not `FAIL()`) when absent.
**When to use:** Any new test that requires a real Vulkan device (as BUILD-01's regression test does — D-01's evidence is explicitly scoped to "a real Vulkan device is present").
**Example:**
```cpp
// Source: SuperGenius/SGProcessingManager/test/capture/capture_smoke_test.cpp:34-40 (existing pattern)
TEST( CaptureSmokeTest, HarnessProducesWellFormedFile )
{
    if ( !sgns::sgprocessing::HasUsableVulkanDevice() )
    {
        GTEST_SKIP() << "No usable Vulkan device found on this host; skipping this GPU-dependent "
                        "smoke test, not failing it.";
    }
    // ...
}
```

### Pattern 2: Double-checked locking around `VulkanInitMutex()`
**What:** Check the init flag unlocked, lock, re-check, then do the real (expensive) work; release before calling out to any function that might re-acquire the same mutex.
**When to use:** Any new code touching `VulkanInitMutex()`. Not new code for this phase (D-03 forbids touching the locking model) — documented here only so the planner recognizes this pattern is already correct and must not be "fixed."
**Example:**
```cpp
// Source: SuperGenius/SGProcessingManager/src/processors/processing_processor_render.cpp:58-66
bool RenderProcessor::InitializeContext()
{
    if ( m_contextInitialized )
        return true;

    std::lock_guard<std::mutex> lock( sgns::sgprocessing::VulkanInitMutex() );

    if ( m_contextInitialized )
        return true;
    // ... real Vulkan instance/device creation ...
}
```

### Pattern 3: CMake ctest-level fail-fast timeout
**What:** Attach an explicit `TIMEOUT` property to a ctest target so a hang becomes a bounded, reported "Timeout" ctest failure instead of hanging the whole suite indefinitely.
**When to use:** Any test exercising a code path with a known historical hang/deadlock risk — exactly BUILD-01's regression test.
**Example:**
```cmake
# Source: SuperGenius/test/src/bridge_race/CMakeLists.txt:27-28 (existing precedent)
# default timeout — own extended TIMEOUT, isolated ctest target.
set_tests_properties(bridge_race_single_burn_test PROPERTIES TIMEOUT 500)
```
Applied analogously to `vulkan_init_concurrency_test` (the target already registered via `addtest()` in `SuperGenius/test/src/processing_vulkan_concurrency/CMakeLists.txt`), planner should add e.g.:
```cmake
set_tests_properties(vulkan_init_concurrency_test PROPERTIES TIMEOUT 60)
```
(Exact seconds value is Claude's discretion at plan time — 60s is generously above the existing test's ~25-iteration concurrent run time on a real GPU; tune based on observed local run duration.)

### Anti-Patterns to Avoid
- **Holding `VulkanInitMutex()` while calling any function that itself acquires it:** This is the exact bug class BUILD-01 describes and `528a92a` fixed. `capability_validator.cpp:220-226`'s comment is the canonical explanation — any future PR touching this area should re-read it before changing lock scope.
- **In-test busy-loop/manual thread-timeout scaffolding:** Given no precedent exists in this codebase's test suite (only in `evmrelay` production code) and the CMake `TIMEOUT` property already satisfies D-03's "fails fast" ask with one line, inventing a hand-rolled `std::thread`+`std::future` timeout wrapper inside the test itself is unnecessary complexity for this phase — see Don't Hand-Roll below.
- **Treating GPU-less CI as a test failure:** `vulkan_gpu_probe.hpp`'s own header comment is explicit: "Callers MUST treat a `false` return as 'skip GPU-dependent work' ... never as a hard error." The new regression test must `GTEST_SKIP()`, not fail, when no real device is present.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| "Fail fast instead of hang" for a test with historical deadlock risk | A custom `std::thread` + `std::promise`/`std::future::wait_for(timeout)` wrapper inside the test body | CMake's built-in `set_tests_properties(<target> PROPERTIES TIMEOUT <seconds>)` | ctest already implements this correctly (kills the process and reports a distinct "Timeout" result) with zero new C++ code; a hand-rolled in-test timeout can't actually terminate a truly-hung call (the guarded thread would leak/detach forever, and the test process itself would still need external killing) — it only reports the hang faster, which ctest's own mechanism already does with less code and an existing project precedent (`bridge_race`). |
| Real-Vulkan-device detection | A bespoke probe reimplementing vk-bootstrap enumeration | `sgns::sgprocessing::HasUsableVulkanDevice()` | Already exists, already self-contained (own throwaway `VkInstance`, no interaction with `RenderProcessor`'s state), already the established GTEST_SKIP-gating convention in this codebase (`capture_smoke_test.cpp`). |

**Key insight:** Every piece of infrastructure D-03's regression test needs (device gating, mutex-safe call path, timeout enforcement) already exists in this codebase as an established, precedented pattern. This phase's only genuinely new code is the test body itself (one `TEST_F`) plus one CMake line — everything else is reuse.

## Common Pitfalls

### Pitfall 1: Re-verifying against a stale/not-yet-rebuilt binary
**What goes wrong:** The original todo (2026-08-10) was almost certainly filed against test binaries built before `528a92a` (2026-08-06's fix) had actually been picked up by a rebuild — `SGProcessingManager/test/` was only wired into ctest discovery by Phase 10's `enable_testing()` ordering fix, so stale binaries could easily have outlived the underlying source fix.
**Why it happens:** Submodule pointer bumps and rebuilds don't always happen atomically with a fix landing; a `.exe` on disk can silently lag its source tree.
**How to avoid:** When executing this phase, do a fresh clean build (or at minimum confirm `git log` timestamps in the submodule are newer than the last build) before treating a test result as evidence either way.
**Warning signs:** A test failing in a way that contradicts a "this was already fixed" claim in CONTEXT.md/STATE.md — first suspect is a stale binary, not a regression.

### Pitfall 2: Treating the D-05 flaky `processing_dispatch_test` file-path failure as in-scope
**What goes wrong:** During D-01's repro, one of four ctest runs hit an unrelated `Failed to open file (Windows): The system cannot find the file specified` error in `processing_dispatch_test`, immediately followed by an apparent stall before the next test printed — easy to conflate with the `VulkanInitMutex` bug.
**Why it happens:** Superficially, "test stalled" pattern-matches the deadlock symptom this phase exists to close.
**How to avoid:** CONTEXT.md D-05 already ruled this out as unrelated (a CWD-relative fixture-path resolution difference between direct `.exe` invocation and `ctest`) and explicitly out of scope. Don't reopen or attempt to fix it in this phase; if it recurs during execution, note it and move on.
**Warning signs:** A single non-reproducing `ctest` run showing an unrelated file-not-found error, with three subsequent clean runs.

### Pitfall 3: Widening BUILD-01's regression coverage beyond the exact scenario D-03 specifies
**What goes wrong:** It's tempting to also add coverage for `HasUsableVulkanDevice()`'s own `VulkanInitMutex()` call site (`vulkan_gpu_probe.cpp:14`) or the MNN processor call sites, since the original todo named `HasUsableVulkanDevice()` as "a second suspect path."
**Why it happens:** The mutex is genuinely shared across many call sites (14 `VulkanInitMutex()` lock sites found via grep across `src/processors/`), and thoroughness instinct suggests testing all of them.
**How to avoid:** D-03 scopes the regression test to exactly one scenario: "`ProcessingManager::Create()` with a real Vulkan device present must return without hanging or throwing." `HasUsableVulkanDevice()`'s lock scope was independently checked in this research (a single, non-nested `lock_guard` around vk-bootstrap instance/device enumeration, torn down before returning — no call to anything that re-acquires the mutex) and is not implicated. Stick to the one scenario CONTEXT.md locked; don't expand scope mid-phase.
**Warning signs:** Plan tasks proposing new tests for MNN processor Vulkan paths or `HasUsableVulkanDevice()` itself — those are out of this phase's locked scope.

## Code Examples

### Existing fixture scaffolding to reuse (from `vulkan_init_concurrency_test.cpp`)
```cpp
// Source: SuperGenius/test/src/processing_vulkan_concurrency/vulkan_init_concurrency_test.cpp:46-72
class VulkanConcurrentInitTest : public ::testing::Test
{
protected:
    static inline std::string binary_path = "";
    static inline std::string data_path   = "";

    static void SetUpTestSuite()
    {
        binary_path = boost::dll::program_location().parent_path().string() + "/";
        data_path   = binary_path + "processing_datatypes/";
    }

    static void TearDownTestSuite() {}

    static std::string LoadAndPatchJson( const std::string &filename )
    {
        std::string file_path = data_path + filename;
        std::ifstream stream( file_path );
        if ( !stream.is_open() )
        {
            return "";
        }
        std::string content( ( std::istreambuf_iterator<char>( stream ) ),
                             std::istreambuf_iterator<char>() );
        return PatchJsonUrisToAbsolute( content, binary_path );
    }
};
```
A new `TEST_F(VulkanConcurrentInitTest, ...)` can call `LoadAndPatchJson("string-processing-definition.json")` (already copied into the test binary's `processing_datatypes/` subdirectory by the existing `CMakeLists.txt`'s `POST_BUILD` copy step) exactly as the existing test does, then call `ProcessingManager::Create(json_str)` directly on the main test thread (no `std::thread` needed — D-03's scenario is a plain single-call regression, not a concurrency scenario; the existing `RepeatedConcurrentInitNoRaceOrCrash` test already covers concurrent access).

### `ProcessingManager::Create()` call/return-value shape
```cpp
// Source: SuperGenius/SGProcessingManager/src/processingbase/ProcessingManager.cpp:426-431
outcome::result<std::shared_ptr<ProcessingManager>> ProcessingManager::Create( const std::string &jsondata )
{
    auto instance = std::shared_ptr<ProcessingManager>( new ProcessingManager() );
    BOOST_OUTCOME_TRY( instance->Init( jsondata ) );
    return instance;
}
```
The regression test's core assertion is simply that this call, given a well-formed job JSON and a real Vulkan device present, returns (does not hang) and yields `has_value() == true` — mirroring how the existing `RepeatedConcurrentInitNoRaceOrCrash` test already checks `mgr_result.has_value()` before proceeding.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|---------------|--------|
| `BuildSnapshot()` called `ensureVulkanDevice()` while holding `VulkanInitMutex()` (implied pre-`528a92a` state, not directly observed in this session — no earlier commit was read) | `ensureVulkanDevice()` called outside the lock; lock only re-acquired briefly afterward to read device properties | `528a92a` ("Fix hang on OSX"), 2026-08-06 | Eliminates the self-deadlock BUILD-01/the 2026-08-10 todo describe; this is the fix this phase verifies and closes |
| `SGProcessingManager/test/` silently unwired from ctest discovery | `enable_testing()` ordering fixed; all suites (including this phase's three named tests) now ctest-discoverable | Phase 10, Plan 10-06 (per STATE.md) | Without this prior fix, the three named tests couldn't have been exercised via `ctest -C Debug` at all, and BUILD-01 would have been unverifiable through the project's normal test-running path |

**Deprecated/outdated:** None identified specific to this phase's narrow scope.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | 60-second `TIMEOUT` value suggested for the CMake property is a reasonable default | Architecture Patterns / Pattern 3 | Low — this is explicitly flagged as Claude's-discretion-at-plan-time in the same section; if the real GPU run takes longer than 60s under CI load, the plan should tune it upward based on an observed local run, not accept 60s blindly |
| A2 | No pre-`528a92a` commit was read to directly observe the "held mutex while calling ensureVulkanDevice" broken state | Summary / State of the Art | Low — the fix's *current* correctness was directly verified by reading the post-fix code and its explanatory comment; the pre-fix state is inferred from the commit message and comment wording, not independently re-created and tested. This does not affect the closure decision (D-01's clean repro against current HEAD is the actual evidence), only the historical narrative. |

**All other claims in this research were verified directly against current HEAD via `Read`/`Grep`/`git log`/`git merge-base`/`ctest -N` in this session — no unverified package names, docs claims, or web-search-derived facts are present.**

## Open Questions

1. **Exact TIMEOUT seconds value for the CMake property**
   - What we know: The precedent (`bridge_race`) uses target-specific values from 180-500s depending on test complexity; `vulkan_init_concurrency_test`'s existing test runs 25 iterations of a 3-thread concurrent-init loop against a real GPU, which is more work than the proposed new single-call regression test but currently has no explicit TIMEOUT at all (relies on ctest's global default).
   - What's unclear: Whether the existing 25-iteration test's real-world duration on the target CI/dev hardware is known/measured.
   - Recommendation: Planner should have the execute-phase task measure one local run's wall time (`ctest --test-dir build/Windows/Debug -R vulkan_init_concurrency_test --verbose`) and set TIMEOUT to a generous multiple (e.g. 3-5x) of the observed duration, rather than guessing a fixed number blind.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| CMake + Visual Studio generator (Windows/Debug build tree) | Building/running the regression test and the two other named tests | ✓ | Existing `build/Windows/Debug` tree present, `ctest -N` lists all three named targets | — |
| Real Vulkan device (discrete/integrated GPU) | D-01's closure evidence and the new regression test's non-skip path | ✓ (this session's dev host: NVIDIA GeForce RTX 4070 Ti SUPER, per CONTEXT.md D-01) | — | `HasUsableVulkanDevice()`-gated `GTEST_SKIP()` on hosts without one (already the established pattern) |
| GoogleTest | New `TEST_F` case | ✓ | Already vendored/linked via `addtest()` | — |

**Missing dependencies with no fallback:** None.
**Missing dependencies with fallback:** None identified beyond the already-solved GPU-presence gating.

## Security Domain

`security_enforcement` is enabled (ASVS level 1, block on `high`) project-wide, but this phase's actual change surface is a single new GoogleTest case plus one CMake `TIMEOUT` property — no new input parsing, authentication, session, or cryptographic code is introduced, and CONTEXT.md D-03/D-04 explicitly forbid modifying `VulkanInitMutex`'s locking model or touching any other repo. The applicable ASVS surface is therefore minimal:

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-------------------|
| V2 Authentication | No | No auth surface touched |
| V3 Session Management | No | No session surface touched |
| V4 Access Control | No | No access-control surface touched |
| V5 Input Validation | Marginal | The new test loads a fixture JSON via the existing `LoadAndPatchJson()` helper, which already handles missing-file gracefully (returns empty string, test aborts via early return) — reuse as-is, no new parsing logic |
| V6 Cryptography | No | No crypto surface touched (the SHA-256 executor-identity hashing in `BuildSnapshot()` is pre-existing and unmodified) |

### Known Threat Patterns for {stack}

Not applicable — this is an internal C++ regression test in a native test binary with no external attack surface (no network listener, no untrusted-user input, no serialization of attacker-controlled data). No STRIDE-relevant threat pattern is introduced by this phase's scope.

## Sources

### Primary (HIGH confidence — verified directly against current repo state this session)
- `SuperGenius/SGProcessingManager/src/capability/capability_validator.cpp:180-260` — `BuildSnapshot()` read in full, confirms D-02's claim
- `SuperGenius/SGProcessingManager/src/processingbase/ProcessingManager.cpp:400-530` — `Create()`/`Init()` read in full, confirms invocation shape
- `SuperGenius/SGProcessingManager/src/processors/processing_processor_render.cpp:1-200` — `InitializeContext()` double-checked-locking pattern confirmed
- `SuperGenius/SGProcessingManager/src/processors/vulkan_gpu_probe.cpp` — `HasUsableVulkanDevice()` read in full, confirms self-contained single-lock scope
- `SuperGenius/SGProcessingManager/include/processingbase/vulkan_init_guard.hpp` — `VulkanInitMutex()` header comment confirms process-wide/reacquired-per-call semantics
- `SuperGenius/SGProcessingManager/test/capture/capture_smoke_test.cpp` — confirmed `HasUsableVulkanDevice()` + `GTEST_SKIP()` gating pattern
- `SuperGenius/test/src/processing_vulkan_concurrency/vulkan_init_concurrency_test.cpp` and its `CMakeLists.txt` — confirmed fixture scaffolding, existing build wiring, and library link path to `HasUsableVulkanDevice()` via `ProcessingBase` → `SGProcessors`
- `SuperGenius/test/src/bridge_race/CMakeLists.txt` — confirmed the codebase's one precedent for `set_tests_properties(... PROPERTIES TIMEOUT N)`
- `SuperGenius/SGProcessingManager` git history (`git log`, `git merge-base --is-ancestor`, `git show -s --format`) — confirmed `528a92a` is a real ancestor of HEAD, dated 2026-08-06, predating the 2026-08-10 todo
- `ctest --test-dir build/Windows/Debug -N` — confirmed all three named tests are live, discoverable ctest targets in the existing build tree referenced by `config.json`'s `test_command`
- `SuperGenius/cmake/functions.cmake` — confirmed `addtest()`'s ctest-registration mechanics (relevant to how TIMEOUT properties layer on top)

### Secondary (MEDIUM confidence)
None used — all findings for this phase were resolvable via direct codebase/git inspection.

### Tertiary (LOW confidence)
None.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new dependencies; all reused components directly inspected in source
- Architecture: HIGH — every code path named in CONTEXT.md was independently re-read against current HEAD and matches exactly
- Pitfalls: HIGH — Pitfall 1/2 are direct restatements of CONTEXT.md's own D-01/D-05 findings; Pitfall 3 is grounded in a fresh grep confirming exactly 14 `VulkanInitMutex()` lock sites and independently checking the one CONTEXT.md flagged as a "second suspect path" is not implicated

**Research date:** 2026-08-20
**Valid until:** Effectively pinned to current HEAD of the `SGProcessingManager` submodule — re-verify commit ancestry (`git merge-base --is-ancestor 528a92a HEAD`) if execution is delayed and the submodule pointer moves before this phase is planned/executed.
