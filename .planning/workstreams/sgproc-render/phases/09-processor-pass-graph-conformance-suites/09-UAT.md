---
status: resolved
phase: 09-processor-pass-graph-conformance-suites
source: [09-VERIFICATION.md]
started: 2026-08-07T01:10:00.000Z
updated: 2026-08-07T03:32:05.000Z
---

## Current Test

[testing complete]

## Tests

### 1. Standalone SGProcessingManager build + submodule-consumption build (TEST-01)
expected: |
  Build SGProcessingManager as a standalone top-level CMake project (not as a
  SuperGenius submodule) and run `ctest` there; separately, confirm
  SuperGenius/develop consuming SGProcessingManager as a submodule produces
  the same passing test results.
result: issue
reported: "CapabilityValidatorTest.RejectUnregisteredPassType fails in SGProcessingManager. As far as SuperGenius procesing_ tests, only processing_dispatch_test is failing, which i'm not sure if that is part of this phase, but should be addressed."
severity: blocker

## Summary

total: 1
passed: 0
issues: 1
pending: 0
skipped: 0
blocked: 0

## Gaps

- truth: "ctest passes with the same results in both the standalone build and the submodule-consumption build (TEST-01)"
  status: resolved
  reason: "User reported: CapabilityValidatorTest.RejectUnregisteredPassType fails in SGProcessingManager."
  severity: blocker
  test: 1
  root_cause: |
    Test-authoring defect, not a regression. CapabilityValidatorTest.RejectUnregisteredPassType
    (SuperGenius/SGProcessingManager/test/capability/capability_validator_test.cpp:126-127)
    asserts the rejection message contains "INFERENCE" or the digit "1", assuming
    PassType::INFERENCE's underlying int value is 1. The actual quicktype-generated enum
    (SuperGenius/SGProcessingManager/generated/PassType.hpp) alphabetizes the schema's enum
    values, so PassType::INFERENCE == 2, not 1. CapabilityValidator::CanExecute()
    (src/capability/capability_validator.cpp:305-312) builds the rejection message from the
    raw numeric value only (never embeds the name "INFERENCE"), so with only a RENDER(3)
    executor registered the actual message is "No executor registered for PassType 2.
    Available: [3]" — satisfying neither disjunct of the test's EXPECT_TRUE. This code path
    only builds under SGProcessingManager's standalone per-platform CMake wrapper; SuperGenius's
    submodule-consumption build never runs it, which is why this UAT round is the first to
    surface it (roadmap TEST-01 flagged standalone-build verification as previously deferred).
  artifacts:
    - path: "SuperGenius/SGProcessingManager/test/capability/capability_validator_test.cpp"
      issue: "Lines 126-127 hardcode PassType::INFERENCE's numeric value as 1; actual generated value is 2"
    - path: "SuperGenius/SGProcessingManager/src/capability/capability_validator.cpp"
      issue: "CanExecute() PASS_TYPE rejection message (lines 305-312) embeds only the raw int, never a human-readable pass-type name"
  missing:
    - "Fix the test assertion to compare against std::to_string(static_cast<int>(PassType::INFERENCE)) computed at test time instead of a hardcoded literal, OR extend CanExecute()'s message to include the pass-type name so the existing \"INFERENCE\" branch is genuinely satisfied"
  debug_session: ".planning/debug/capability-validator-reject-unregistered.md"

- truth: "ctest passes with the same results in both the standalone build and the submodule-consumption build (TEST-01)"
  status: resolved
  reason: "User reported: processing_dispatch_test fails in SuperGenius (only processing_ test failing there); unsure if in scope for this phase but flagged for investigation. Bug A of 2 found in this test: working-directory-relative fixture path resolution."
  severity: blocker
  test: 1
  root_cause: |
    Pre-existing bug, NOT caused by Phase 09. SuperGenius/cmake/functions.cmake's addtest()
    calls add_test() with no explicit WORKING_DIRECTORY, so CTest defaults the test's cwd to
    the source-tree-mirrored build dir, not the binary's own directory where the
    processing_dispatch/*.glsl and *.json fixtures actually live. The test's JSON loading is
    cwd-independent, but the file://processing_dispatch/*.glsl shader-source URLs referenced
    inside that JSON fail to resolve under ctest's cwd, feed an empty buffer to shaderc, and
    produce a spurious "#version: Desktop shaders... require version 140" error instead of a
    real syntax error. Already discovered, documented, and explicitly deferred in Phase 03
    (deferred-items.md item DI-03-01-01) — confirmed present even before Phase 03 plan 03-01's
    own changes. 09-VERIFICATION.md's attribution to Phase 08 commit 47bd0bd8 is only true as
    "last commit touching the file" (an unrelated 2-line accessor edit); the bug itself
    long predates that commit.
  artifacts:
    - path: "SuperGenius/cmake/functions.cmake"
      issue: "addtest()'s add_test() call has no explicit WORKING_DIRECTORY, so ctest's cwd doesn't match the fixture files' actual location next to the test binary"
    - path: ".planning/workstreams/sgproc-render/phases/03-renderprocessor-implementation-determinism/deferred-items.md"
      issue: "Prior disclosure of this exact issue as DI-03-01-01, deferred rather than fixed"
  missing:
    - "Add an explicit WORKING_DIRECTORY (e.g. $<TARGET_FILE_DIR:${test_name}>) to addtest()'s add_test() call, OR fix the file:// URI resolver to resolve relative to the binary's location instead of cwd"
  debug_session: ".planning/debug/processing-dispatch-test-failure.md"

- truth: "ctest passes with the same results in both the standalone build and the submodule-consumption build (TEST-01)"
  status: resolved
  reason: "Bug B of 2 found while investigating processing_dispatch_test: RenderPassEndToEndProducesVerifiedOutputHash asserts a non-empty combinedHash that the pipeline never populates for outputs-less render passes."
  severity: blocker
  test: 1
  root_cause: |
    Pre-existing bug from Phase 08, NOT caused by Phase 09, and not previously disclosed.
    ProcessingManager::Process()'s ProcessOutput assembly block
    (SGProcessingManager/src/processingbase/ProcessingManager.cpp, introduced by Phase 08
    submodule commit b9c445b "Structured Artifacts & Execution Manifests") gates ALL
    artifact/manifest/combinedHash population behind
    `if (processResult.output_buffers && !outputs.empty())`. The happy-path render fixture
    (test/src/processing_dispatch/render-pass-happy-path-definition.json, authored in Phase 03,
    never modified since) declares "outputs": [], so the gate never fires and
    output.combinedHash stays empty even though Process() genuinely succeeds and the render
    pipeline executes end-to-end. Confirmed by running the .exe directly with a correct cwd
    (bypassing Bug A): 10/11 sub-tests pass, but RenderPassEndToEndProducesVerifiedOutputHash
    still fails on ASSERT_EQ(hash.size(), 32u).
    RenderPassSameNodeRepeatedExecutionProducesBitExactHash doesn't independently check
    hash.size(), only that its 10 iterations match each other — so it passes vacuously (10
    empty vectors compared to each other) and silently masks this bug under direct invocation.
    git log -L confirms Phase 09 (commit c6f993e, plan 09-11) touched only an unrelated
    format-defaulting sub-block a few lines below this gate, not the gate itself.
  artifacts:
    - path: "SGProcessingManager/src/processingbase/ProcessingManager.cpp"
      issue: "ProcessOutput assembly gates combinedHash population behind !outputs.empty(), so outputs-less render passes never get a populated hash"
    - path: "SuperGenius/test/src/processing_dispatch/render-pass-happy-path-definition.json"
      issue: "Declares \"outputs\": [], which triggers the gate to skip combinedHash population for this fixture"
    - path: "SuperGenius/test/src/processing_dispatch/processing_dispatch_test.cpp"
      issue: "RenderPassSameNodeRepeatedExecutionProducesBitExactHash doesn't assert hash.size()==32 per iteration, so it passes vacuously on empty hashes and silently masks this bug"
  missing:
    - "Add a non-empty outputs entry to render-pass-happy-path-definition.json matching the render pass's actual output, OR change the ProcessingManager.cpp gate to compute combinedHash independent of whether outputs is declared (e.g. hash the raw output buffers directly when outputs is empty)"
    - "Strengthen RenderPassSameNodeRepeatedExecutionProducesBitExactHash to assert hash.size() == 32 per iteration so it can't pass vacuously on empty hashes"
  debug_session: ".planning/debug/processing-dispatch-test-failure.md"
