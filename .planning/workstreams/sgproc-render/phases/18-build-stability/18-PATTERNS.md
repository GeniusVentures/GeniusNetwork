# Phase 18: Build Stability - Pattern Map

**Mapped:** 2026-08-20
**Files analyzed:** 2 (both existing files, modified in place — no new files)
**Analogs found:** 2 / 2

This phase is verify-and-close (BUILD-01). Per CONTEXT.md D-03/RESEARCH.md, the only code
changes are: (1) one new `TEST_F` appended to an existing test file, reusing that file's own
fixture scaffolding as its direct analog, and (2) one `set_tests_properties(...TIMEOUT...)`
CMake line, following the `bridge_race` precedent exactly. No production code changes. No new
files. Because the "analog" for each change is largely the same file being modified, this map
emphasizes exact reusable code blocks and precedent lines rather than a broad codebase survey.

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `SuperGenius/test/src/processing_vulkan_concurrency/vulkan_init_concurrency_test.cpp` (add one `TEST_F`) | test | request-response (single synchronous call, assert no-hang/no-throw) | same file's own `VulkanConcurrentInitTest` fixture (lines 46-72) + `capture_smoke_test.cpp`'s `HasUsableVulkanDevice()`/`GTEST_SKIP()` gate (lines 34-40) | exact (fixture reuse) / exact (skip-gate reuse) |
| `SuperGenius/test/src/processing_vulkan_concurrency/CMakeLists.txt` (add one `set_tests_properties` line) | config | batch (CI/build tooling) | `SuperGenius/test/src/bridge_race/CMakeLists.txt` line 28 | exact |
| Evidence-trail documentation (phase completion doc, not source) | — | — | Phase 13/19 "honest-reporting" convention referenced in CONTEXT.md D-03/`code_context` | pattern reference, no single analog file needed |

## Pattern Assignments

### `vulkan_init_concurrency_test.cpp` — new `TEST_F` (test, request-response)

**Analog:** the file's own `VulkanConcurrentInitTest` fixture + `capture_smoke_test.cpp`'s skip-gate pattern.

**Imports already present in this file** (lines 1-13) — no new includes should be needed; the
new test uses only what's already pulled in:
```cpp
#include <gtest/gtest.h>

#include <fstream>
#include <memory>
#include <iostream>
#include <regex>
#include <thread>
#include <future>
#include <vector>
#include <boost/dll.hpp>
#include <boost/asio/io_context.hpp>
#include <processingbase/ProcessingManager.hpp>
#include <processors/processing_processor_render.hpp>
```
If the new test calls `HasUsableVulkanDevice()` directly (recommended, per RESEARCH.md), add:
```cpp
#include <processors/vulkan_gpu_probe.hpp>
```

**Fixture to reuse verbatim** (lines 46-72) — do not duplicate `SetUpTestSuite`/`LoadAndPatchJson`,
just add a new `TEST_F` against the same `VulkanConcurrentInitTest` class:
```cpp
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

**Device-gating pattern to copy** (source: `SuperGenius/SGProcessingManager/test/capture/capture_smoke_test.cpp:34-40`):
```cpp
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
Apply the same `if (!HasUsableVulkanDevice()) { GTEST_SKIP() << "..."; }` guard as the first line
of the new `TEST_F` body — this is the established, single precedent in this codebase for
gating a GPU-dependent test to degrade gracefully on GPU-less hosts. Do not `FAIL()`.

**Core assertion pattern to copy** (source: same file, existing `RepeatedConcurrentInitNoRaceOrCrash`,
lines 100-105 — the `mgr_result.has_value()` check is the existing idiom for "did `Create()`
succeed"):
```cpp
std::string json_str = LoadAndPatchJson( "string-processing-definition.json" );
if ( json_str.empty() ) return;

auto mgr_result = sgns::sgprocessing::ProcessingManager::Create( json_str );
if ( !mgr_result.has_value() ) return;
auto manager = mgr_result.value();
```
For the new regression test, replace the early-return style with an explicit gtest assertion
(the existing concurrent test uses early-return because it's inside a worker lambda; the new
single-call test runs on the main test thread, so use plain assertions instead):
```cpp
ASSERT_FALSE( json_str.empty() ) << "fixture JSON failed to load";
EXPECT_NO_THROW(
    {
        auto mgr_result = sgns::sgprocessing::ProcessingManager::Create( json_str );
        EXPECT_TRUE( mgr_result.has_value() );
    } );
```

**`ProcessingManager::Create()` signature/shape being tested** (source:
`SuperGenius/SGProcessingManager/src/processingbase/ProcessingManager.cpp:426-431`):
```cpp
outcome::result<std::shared_ptr<ProcessingManager>> ProcessingManager::Create( const std::string &jsondata )
{
    auto instance = std::shared_ptr<ProcessingManager>( new ProcessingManager() );
    BOOST_OUTCOME_TRY( instance->Init( jsondata ) );
    return instance;
}
```

**No new namespace/braces needed** — the new `TEST_F` goes inside the existing `namespace sgns { ... }`
block (opened line 15, closed line 165), immediately after the existing
`RepeatedConcurrentInitNoRaceOrCrash` test (ends line 164).

---

### `vulkan_init_concurrency_test/CMakeLists.txt` — add `TIMEOUT` property (config, batch)

**Analog:** `SuperGenius/test/src/bridge_race/CMakeLists.txt:26-28`
```cmake
# D-15/Pitfall 2: 11-node startup cost is higher than the fast bridge_e2e suite's
# default timeout — own extended TIMEOUT, isolated ctest target.
set_tests_properties(bridge_race_single_burn_test PROPERTIES TIMEOUT 500)
```
Other `bridge_race` targets in the same file use lower values for lighter tests (180s for
`bridge_race_batch_test`, `bridge_race_fault_rpc_test`, `bridge_race_fault_kill_test`,
`bridge_race_fault_partition_test` — lines 55, 83, 110, 137) — establishing that the value is
tuned per-target based on observed test cost, not copy-pasted blindly.

**Current file** (`SuperGenius/test/src/processing_vulkan_concurrency/CMakeLists.txt`, full
contents, 28 lines) has no existing `set_tests_properties` call. Append, following the same
comment-then-property style, directly after the `target_link_libraries` block (after line 10,
before or after the `add_custom_command` fixture-copy steps — placement relative to those is
not load-bearing):
```cmake
# BUILD-01/Phase 18: regression test calls ProcessingManager::Create() against a real
# Vulkan device; give it an explicit fail-fast TIMEOUT so a future VulkanInitMutex
# re-entrancy regression produces a ctest Timeout result instead of hanging the suite.
set_tests_properties(vulkan_init_concurrency_test PROPERTIES TIMEOUT <N>)
```
Per RESEARCH.md's Open Question, `<N>` should be set from an observed local
`ctest --test-dir build/Windows/Debug -R vulkan_init_concurrency_test --verbose` run time,
generously multiplied (3-5x), rather than guessed — the existing 25-iteration
`RepeatedConcurrentInitNoRaceOrCrash` test plus the new single-call test both run under this
one target/TIMEOUT since `addtest()` registers the whole binary as one ctest target.

## Shared Patterns

### GTEST_SKIP-gated real-device test
**Source:** `SuperGenius/SGProcessingManager/test/capture/capture_smoke_test.cpp:34-40`
**Apply to:** the new `TEST_F` in `vulkan_init_concurrency_test.cpp` — any GPU-dependent test must
skip (not fail) when `HasUsableVulkanDevice()` returns false.

### Double-checked locking around `VulkanInitMutex()` — reference only, not to be modified
**Source:** `SuperGenius/SGProcessingManager/src/processors/processing_processor_render.cpp:58-66`
```cpp
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
**Apply to:** nothing new this phase — documented so the planner/executor recognizes this is
already correct (per D-02/D-03) and must NOT be touched. Also see the explanatory comment at
`capability_validator.cpp:220-226` (excerpted above) which documents exactly why
`ensureVulkanDevice()` is called outside the lock in `BuildSnapshot()` — this is the fix (`528a92a`)
being verified-and-closed, not re-derived.

### CTest fail-fast TIMEOUT
**Source:** `SuperGenius/test/src/bridge_race/CMakeLists.txt:28,55,83,110,137`
**Apply to:** `SuperGenius/test/src/processing_vulkan_concurrency/CMakeLists.txt` (the one CMake
change this phase makes).

### Honest-reporting / evidence-trail documentation convention
**Source:** referenced in CONTEXT.md as "Phase 13/19's honest-reporting convention" — no single
source file to excerpt (it's a documentation convention, not code). **Apply to:** whatever
phase-completion/evidence document the planner has the execute step produce, documenting D-01/D-02's
already-fixed-and-verified finding rather than asserting a new fix.

## No Analog Found

None — both changes for this phase have exact, directly-inspected precedent in the codebase
(the file's own fixture for the test; `bridge_race`'s `CMakeLists.txt` for the TIMEOUT property).

## Metadata

**Analog search scope:** `SuperGenius/test/src/processing_vulkan_concurrency/`,
`SuperGenius/test/src/bridge_race/`, `SuperGenius/SGProcessingManager/test/capture/`,
`SuperGenius/SGProcessingManager/src/capability/`, `SuperGenius/SGProcessingManager/src/processors/`,
`SuperGenius/SGProcessingManager/src/processingbase/`
**Files scanned:** 6 (all read directly per RESEARCH.md's own Sources list plus 3 additional
direct reads this session: `vulkan_init_concurrency_test.cpp` in full, its `CMakeLists.txt` in
full, `bridge_race/CMakeLists.txt` in full, `capture_smoke_test.cpp` lines 1-45,
`capability_validator.cpp` lines 205-239)
**Pattern extraction date:** 2026-08-20
