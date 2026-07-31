# Phase 4: Cross-Platform Build, CI & End-to-End Verification - Pattern Map

**Mapped:** 2026-07-31
**Files analyzed:** 5 (CI matrix, GPU probe, CTest registration, E2E fixture/test, concurrency verification)
**Analogs found:** 5 / 5 (all role-match or exact; no "no analog" bucket)

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|--------------------|------|-----------|-----------------|----------------|
| `SuperGenius/.github/workflows/cmake.yml` (extend per-platform jobs with GPU-probe step + gated ctest label) | config (CI workflow) | batch (build→test pipeline) | itself — existing `build` job's Linux/Windows/OSX "Configure host" + "Run tests" steps (lines 513-544, 712-735) | exact (modify-in-place, not new file) |
| New GPU-probe helper (e.g. `SGProcessingManager/.../vulkan_gpu_probe.{hpp,cpp}` or small standalone CLI/CTest fixture) | utility | request-response (query device, return status) | `SGProcessingManager/src/processors/processing_processor_render.cpp:19-23,38-146` (`IsAcceptable` + `InitializeContext`'s vk-bootstrap enumerate/select/filter sequence) | role-match (same VkInstance/vkb enumeration shape, simpler: probe-only, no VkDevice creation needed unless probe wants to confirm device creation too) |
| `test/src/<new-render-ci-dir>/CMakeLists.txt` (CTest registration for GPU-gated tests) | config (CMake/CTest) | batch | `test/src/processing_dispatch/CMakeLists.txt`, `test/src/processing_vulkan_concurrency/CMakeLists.txt` (both use `addtest()` + fixture-copy `add_custom_command`) | exact |
| E2E render-job test (new test case or promotion of existing) | test | request-response (submit job → get hash) | `test/src/processing_dispatch/processing_dispatch_test.cpp:265-305` (`RenderPassSameNodeRepeatedExecutionProducesBitExactHash`) and `test/src/processing_schema/processing_schema_test.cpp:210-248` (`PosenetJobTest`, real-job-fixture convention) | exact (dispatch test) / role-match (schema test, for "real fixture" convention) |
| E2E-03 verification (no new file — confirm existing test still passes) | test | event-driven (concurrent threads) | `test/src/processing_vulkan_concurrency/vulkan_init_concurrency_test.cpp:1-100+` (`VulkanConcurrentInitTest.RepeatedConcurrentInitNoRaceOrCrash`) | exact (verification target, not a new analog-copy) |

## Pattern Assignments

### `SuperGenius/.github/workflows/cmake.yml` (CI config, modified in place)

**Analog:** itself (same file, existing per-platform host-config + test-run steps)

**Runner resolution — already reusable as-is** (lines 98-196):
The `resolve-runners` job outputs `linux_x64`/`linux_arm`/`windows`/`mac` labels, falling back to GitHub-hosted runners when self-hosted (`sg-ubuntu-linux`, `sg-arm-linux`, `SG-WIN11`, `gv-OSX-Large`) is unavailable/busy. New render-CI steps ride the same `runs-on: ${{ fromJson(needs.resolve-runners.outputs[matrix.runner_key]) }}` (line 202) — no new runner-selection logic needed (D-36).

**Existing per-platform Vulkan/host setup** (lines 513-544):
```yaml
- name: Configure Linux host
  if: ${{ runner.os == 'Linux' }}
  run: |
    ...
    sudo apt install ccache ninja-build libvulkan-dev libsecret-1-dev dbus gnome-keyring -y
    echo "CMAKE_GENERATOR=Ninja" >> $GITHUB_ENV

- name: Configure Windows host
  if: ${{ runner.os == 'Windows' }}
  run: choco install ccache -A

- name: Configure macOS host
  if: ${{ runner.os == 'macOS' }}
  run: |
    brew install ninja bash gnu-tar
    ...
```
Note: Linux install is loader-only (`libvulkan-dev`), no ICD (D-32/D-33 context) — matches CONTEXT.md's "CI Vulkan setup today is loader-only" note. No changes needed to these steps; the Vulkan *driver/ICD* question is exactly what D-31 says CI does NOT solve this phase — the GPU probe (new step) determines usability at runtime instead.

**Existing per-platform "Run tests" steps** (lines 712-735) — this is where the GPU-probe-gated CTest run happens; **no change needed to the invocation shape itself** (per code_context "Integration Points" — gating is inside test binaries via D-32/D-34, not via conditional `ctest` args):
```yaml
- name: Run tests (Windows)
  working-directory: ${{ github.workspace }}/SuperGenius/${{ env.BUILD_DIRECTORY }}
  if: ${{ matrix.build-type == 'Release' && matrix.target == 'Windows' }}
  run: ctest . -j -C ${{ matrix.build-type }} --output-on-failure

- name: Run tests (Linux)
  working-directory: ${{ github.workspace }}/SuperGenius/${{ env.BUILD_DIRECTORY }}
  if: ${{ matrix.target == 'Linux' }}
  shell: bash
  run: |
    dbus-run-session -- bash -c '\
      ...
      ctest . -j -C ${{ matrix.build-type }} --output-on-failure'

- name: Run tests (OSX)
  working-directory: ${{ github.workspace }}/SuperGenius/${{ env.BUILD_DIRECTORY }}
  if: ${{ matrix.target == 'OSX' }}
  run: ctest . --verbose -j -C ${{ matrix.build-type }}
```
**Planner note:** if a CI-visible "annotation" is wanted for D-34's skip case (beyond GTest's own skip/log output), add a lightweight step after `ctest` that greps the xunit/log output for the probe's skip marker and echoes to `$GITHUB_STEP_SUMMARY` (see `resolve-runners` job's own `>> "$GITHUB_STEP_SUMMARY"` usage at lines 149-159 for the established idiom in this file).

**Matrix targets in scope** (lines 210-240): only `Linux`, `Windows`, `OSX` entries get new render-CI steps; `Android`/`iOS` matrix entries are untouched (RenderProcessor out of scope there per CTX-01, matches D-36).

---

### GPU-probe mechanism (new file)

**Analog:** `SuperGenius/SGProcessingManager/src/processors/processing_processor_render.cpp:19-23` (`IsAcceptable`) and `:38-146` (`InitializeContext`)

**Device-type filter to mirror exactly** (lines 19-23):
```cpp
bool RenderProcessor::IsAcceptable( VkPhysicalDeviceType type )
{
    return type == VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU
        || type == VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU;
}
```

**vk-bootstrap enumeration/selection pattern to mirror** (lines 48-92, condensed):
```cpp
#include <VkBootstrap.h>
...
vkb::InstanceBuilder instance_builder;
auto inst_ret = instance_builder
                    .set_app_name( "SGProcessingManager RenderProcessor" )
                    .set_app_version( 1, 0, 0 )
                    .request_validation_layers( false )
                    .build();
if ( !inst_ret ) { /* error, return false */ }
auto vkb_instance = inst_ret.value();

vkb::PhysicalDeviceSelector selector( vkb_instance );
// Headless/offscreen — no VkSurfaceKHR ever exists; disable present requirement.
selector.require_present( false );
auto devices_ret = selector.select_devices();
if ( !devices_ret ) { vkb::destroy_instance( vkb_instance ); return false; }

auto devices = devices_ret.value();
devices.erase(
    std::remove_if( devices.begin(), devices.end(),
        []( const vkb::PhysicalDevice &d ) {
            return !IsAcceptable( d.properties.deviceType );
        } ),
    devices.end() );

if ( devices.empty() )
{
    // no acceptable physical device found -- this is the probe's "skip" signal
    vkb::destroy_instance( vkb_instance );
    return false;
}
```
**Probe-specific simplification:** the probe only needs through `select_devices()` + the `IsAcceptable` filter + `devices.empty()` check (i.e., "is there a usable VkInstance and at least one DISCRETE/INTEGRATED_GPU device") — it does NOT need `DeviceBuilder`/queue creation (lines 104-142 of the analog), since the probe's job is existence-detection, not context setup for actual rendering. Reuse `RenderProcessor::IsAcceptable` directly if the probe lives inside `SGProcessingManager` (same TU/library) rather than reimplementing the filter — avoids drift between the probe's definition of "usable" and `RenderProcessor`'s own.

**Suggested exposure shape:** a small free function (e.g. `bool sgns::sgprocessing::HasUsableVulkanDevice()`) callable both from a standalone CLI probe (for a CI step to invoke with plain exit-code semantics) and from GTest fixtures (via a shared `SetUpTestSuite`/skip-guard, following GTest's `GTEST_SKIP()` idiom) — planner should confirm final shape; CONTEXT.md leaves exact CMake/CTest label scheme to Claude's discretion.

---

### Test CTest registration (new `CMakeLists.txt` in new test dir)

**Analog:** `SuperGenius/test/src/processing_dispatch/CMakeLists.txt` and `SuperGenius/test/src/processing_vulkan_concurrency/CMakeLists.txt`

**`addtest()` macro definition** (`SuperGenius/cmake/functions.cmake:8-27`):
```cmake
function(addtest test_name)
    add_executable(${test_name} ${ARGN})
    addtest_part(${test_name} ${ARGN})
    target_link_libraries(${test_name}
        GTest::gtest_main
        GTest::gmock_main
    )
    file(MAKE_DIRECTORY ${CMAKE_BINARY_DIR}/xunit)
    set(xml_output "--gtest_output=xml:${CMAKE_BINARY_DIR}/xunit/xunit-${test_name}.xml")
    add_test(
        NAME ${test_name}
        COMMAND $<TARGET_FILE:${test_name}> ${xml_output}
    )
    set_target_properties(${test_name} PROPERTIES
        RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/test_bin
        ARCHIVE_OUTPUT_PATH ${CMAKE_BINARY_DIR}/test_lib
        LIBRARY_OUTPUT_PATH ${CMAKE_BINARY_DIR}/test_lib
    )
    disable_clang_tidy(${test_name})
endfunction()
```
Note: gating (D-32/D-34) is **inside the test binary** (probe-and-skip via `GTEST_SKIP()`), not at the CMake/`add_test` level — `addtest()` itself needs no modification; a GPU-gated test is registered exactly like any other.

**Test registration + fixture-copy convention** (`processing_dispatch/CMakeLists.txt:1-30`):
```cmake
addtest(processing_dispatch_test
    processing_dispatch_test.cpp
)

target_include_directories(processing_dispatch_test PRIVATE ${AsyncIOManager_INCLUDE_DIR})

target_link_libraries(processing_dispatch_test
    nlohmann_json
    ProcessingBase
)

add_custom_command(TARGET processing_dispatch_test POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E make_directory
    "$<TARGET_FILE_DIR:processing_dispatch_test>/processing_dispatch/"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
    "${CMAKE_CURRENT_SOURCE_DIR}/render-pass-happy-path-definition.json"
    ...
    "$<TARGET_FILE_DIR:processing_dispatch_test>/processing_dispatch/"
    COMMENT "Copying dispatch test fixtures"
)
```
If E2E-01's test is a **new distinct test/dir** rather than a promotion of the existing dispatch test (per D-35's open question), its `CMakeLists.txt` should follow this exact shape: `addtest(<name> <name>.cpp)`, link `nlohmann_json` + `ProcessingBase`, and a `POST_BUILD` fixture-copy of the real render-pass job JSON into a same-named subfolder next to the test binary (mirrors both `processing_dispatch` and `processing_schema`'s `data/`-copy convention).

---

### E2E render-job test (new test case or promotion)

**Analog 1 (primary):** `test/src/processing_dispatch/processing_dispatch_test.cpp:265-305`
```cpp
TEST_F( ProcessingDispatchTest, RenderPassSameNodeRepeatedExecutionProducesBitExactHash )
{
    WriteHappyPathVertexData();

    std::string json_data = LoadJson( "render-pass-happy-path-definition.json" );
    ASSERT_FALSE( json_data.empty() ) << "Could not load happy-path fixture";

    std::vector<std::vector<uint8_t>> allHashes;

    for ( int i = 0; i < 10; ++i )
    {
        auto mgr_result = sgns::sgprocessing::ProcessingManager::Create( json_data );
        ASSERT_TRUE( mgr_result.has_value() ) << "Iteration " << i << ": ProcessingManager::Create failed";

        auto manager = mgr_result.value();

        sgns::ModelNode model_node;
        model_node.set_source( std::string( "input:renderInput" ) );

        auto ioc = std::make_shared<boost::asio::io_context>();
        std::vector<std::vector<uint8_t>> chunkhashes;
        std::vector<std::string> output_locations;

        auto process_result = manager->Process( ioc, chunkhashes, model_node, output_locations );

        ASSERT_TRUE( process_result.has_value() )
            << "Iteration " << i << " failed: ..."
            << " -- a real Vulkan-capable GPU is a hard prerequisite for this test; ...";

        allHashes.push_back( process_result.value() );
    }
    // ... compare allHashes[i] == allHashes[0]
}
```
This is architecturally the E2E-01 shape (real `ProcessingManager::Create()` → `Process()` → verified hash). Per D-35, **planner must decide during planning** whether this test (possibly relabeled/tagged as GPU-gated per D-32) already satisfies E2E-01, or whether a conceptually distinct fixture is warranted to separate DETV-01's "is it deterministic" concern from E2E-01's "is it a real job definition" concern. If distinct, the loop/hash-comparison scaffolding above should be simplified to a single-run "submit → get hash → assert success" shape (no 10x repeat — that's DETV-01's job).

**Analog 2 (real-job-fixture convention):** `test/src/processing_schema/processing_schema_test.cpp:210-248` (`PosenetJobTest`)
```cpp
TEST_F( ProcessingSchemaTest, PosenetJobTest ) {
    std::string bin_path  = boost::dll::program_location().parent_path().string() + "/";
    std::string data_path = bin_path + "./processing_schema/";

    std::string   instance_file = data_path + "posenet-processing-job.json";
    std::ifstream instance_stream( instance_file );
    ASSERT_TRUE( instance_stream.is_open() ) << "Failed to open instance file: " << instance_file;

    std::string instance_str( ( std::istreambuf_iterator<char>( instance_stream ) ),
                              std::istreambuf_iterator<char>() );
    instance_stream.close();
    ASSERT_FALSE( instance_str.empty() ) << "Instance file is empty";

    auto data = nlohmann::json::parse( instance_str );
    sgns::SgnsProcessing processing;
    sgns::from_json( data, processing );
    ASSERT_EQ( processing.get_name(), "posenet-inference" );
    ...
}
```
Establishes the project convention: load a **real, full job-definition JSON fixture** checked into `test/src/<dir>/` (not synthetic minimal JSON), parse/execute it, assert on real field values. E2E-01's render test (whichever shape D-35 resolves to) should load a real render-pass job definition fixture the same way — `processing_dispatch_test.cpp`'s existing `render-pass-happy-path-definition.json` (used by the analog above) already qualifies as this kind of fixture.

---

### E2E-03 concurrency verification (no new file expected)

**Analog / verification target:** `test/src/processing_vulkan_concurrency/vulkan_init_concurrency_test.cpp:1-100+`
```cpp
class VulkanConcurrentInitTest : public ::testing::Test
{
protected:
    static inline std::string binary_path = "";
    static inline std::string data_path   = "";
    static void SetUpTestSuite() { ... }
    static std::string LoadAndPatchJson( const std::string &filename ) { ... }
};

TEST_F( VulkanConcurrentInitTest, RepeatedConcurrentInitNoRaceOrCrash )
{
    constexpr int kIterations = 25;
    for ( int iter = 0; iter < kIterations; ++iter )
    {
        std::promise<void> releaseGate;
        std::shared_future<void> releaseFuture( releaseGate.get_future() );
        std::vector<std::thread> threads;
        threads.emplace_back( [&releaseFuture, this]() {
            releaseFuture.wait();
            std::string json_str = LoadAndPatchJson( "string-processing-definition.json" );
            // ... MNN string job
        } );
        // ... 2 more threads: MNN texture3d job, RenderProcessor::StartProcessing directly
    }
}
```
Registered via `addtest(vulkan_init_concurrency_test ...)` in `test/src/processing_vulkan_concurrency/CMakeLists.txt`, already runs under every CI matrix job's `ctest` invocation. Per D-37, Phase 4 planner should treat this as a **confirm-still-passes** task post-CI-changes rather than new authoring — no pattern extraction needed beyond this reference unless a coverage gap is found during planning.

## Shared Patterns

### GTest skip idiom for GPU-gated tests (planner to introduce; no existing GTest-skip precedent found in this codebase)
No existing test in this codebase currently uses `GTEST_SKIP()`. D-34 requires GPU-gated tests to skip-with-annotation (not silently pass, not hard-fail) when the probe finds no device. Standard GTest convention (external, not codebase-native) to introduce:
```cpp
if ( !sgns::sgprocessing::HasUsableVulkanDevice() )
{
    GTEST_SKIP() << "No usable Vulkan device (DISCRETE_GPU/INTEGRATED_GPU) found by probe; "
                    "skipping GPU-dependent test.";
}
```
This produces a CTest-visible "SKIPPED" (not "PASSED") result and an xunit `<skipped>` entry, satisfying D-34's "clear CI annotation, not silently passed" requirement. Apply to: pipeline-construction test, draw+readback test, N>=10 determinism test (the existing `RenderPassSameNodeRepeatedExecutionProducesBitExactHash` test at `processing_dispatch_test.cpp:265` should gain this guard too, since it currently `ASSERT_TRUE`-hard-fails when no GPU is present — see its own comment at line 293 acknowledging "no software fallback exists").

### `addtest()` CTest registration
**Source:** `SuperGenius/cmake/functions.cmake:8-27`
**Apply to:** any new render-CI test target (GPU probe test, E2E fixture test if distinct from existing dispatch test)

### Real-job-definition fixture convention
**Source:** `SuperGenius/test/src/processing_schema/processing_schema_test.cpp:210-248` (`posenet-processing-job.json`), `SuperGenius/test/src/processing_dispatch/render-pass-happy-path-definition.json`
**Apply to:** E2E-01's render test — full realistic JSON checked into `test/src/<dir>/`, copied post-build via `add_custom_command` into a same-named subfolder next to the test binary, loaded via `boost::dll::program_location().parent_path()` + relative path (see both analogs' identical `bin_path`/`data_path` idiom).

### CI runner resolution (no changes needed, reuse as-is)
**Source:** `SuperGenius/.github/workflows/cmake.yml:98-196` (`resolve-runners` job)
**Apply to:** all new render-CI steps — ride existing `matrix.runner_key` → `resolve-runners` output resolution, no new runner logic.

## No Analog Found

None — all 5 classified files/changes have at least a role-match analog in the existing codebase (see table above). This phase is additive CI/test-infrastructure work built directly on Phase 1/3 precedent (vk-bootstrap enumeration, `addtest()`, real-job-fixture convention), not a greenfield pattern area.

## Metadata

**Analog search scope:** `SuperGenius/.github/workflows/cmake.yml`, `SuperGenius/cmake/functions.cmake`, `SuperGenius/SGProcessingManager/src/processors/processing_processor_render.cpp`, `SuperGenius/test/src/processing_dispatch/`, `SuperGenius/test/src/processing_schema/`, `SuperGenius/test/src/processing_vulkan_concurrency/`
**Files scanned:** 9 (1 CI workflow, 1 cmake functions file, 1 processor source file, 3 test `.cpp` files, 3 test `CMakeLists.txt` files)
**Pattern extraction date:** 2026-07-31
