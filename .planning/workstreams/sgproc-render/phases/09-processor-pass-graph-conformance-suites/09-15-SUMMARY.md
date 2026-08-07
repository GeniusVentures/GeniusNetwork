---
phase: 09-processor-pass-graph-conformance-suites
plan: 15
subsystem: testing
tags: [ctest, cmake, render-processor, combinedHash, gap-closure]

# Dependency graph
requires:
  - phase: 09-processor-pass-graph-conformance-suites
    provides: "Phase 08's Artifact/ExecutionManifest/combinedHash assembly pipeline in ProcessingManager::Process() (unchanged, already correct); plans 09-01..09-14"
provides:
  - "processing_dispatch_test's ctest WORKING_DIRECTORY explicitly scoped to its own binary directory"
  - "render-pass-happy-path-definition.json declares a real outputs[0] entry, activating the existing artifact/manifest/combinedHash assembly for this fixture"
  - "RenderPassSameNodeRepeatedExecutionProducesBitExactHash's per-iteration 32-byte hash assertion, closing the vacuous-pass-on-empty-hashes gap"
affects: [processing-dispatch-test, ctest-topology]

# Tech tracking
tech-stack:
  added: []
  patterns: ["Target-scoped set_tests_properties(... WORKING_DIRECTORY ...) override instead of modifying the shared addtest() CMake helper, to avoid affecting the other ~60 targets built through it"]

key-files:
  created: []
  modified:
    - SuperGenius/test/src/processing_dispatch/CMakeLists.txt
    - SuperGenius/test/src/processing_dispatch/render-pass-happy-path-definition.json
    - SuperGenius/test/src/processing_dispatch/processing_dispatch_test.cpp

key-decisions:
  - "Fixed processing_dispatch_test's ctest WORKING_DIRECTORY via a single-target set_tests_properties() override rather than touching cmake/functions.cmake's shared addtest() helper, so none of the ~60 other SuperGenius ctest targets change behavior"
  - "Gave the happy-path fixture a real outputs[0] entry mirroring the already-proven regression-b-parseblocksize-model-only.json pattern, rather than modifying ProcessingManager.cpp's already-correct !outputs.empty() gate"
  - "Bound the per-iteration combinedHash to a named iterHash local with its own ASSERT_EQ(size()==32) check before pushing into allHashes, so a future regression that empties the hash again cannot pass vacuously by comparing 10 equal-but-empty vectors"

requirements-completed: [TEST-01]

coverage:
  - id: D1
    description: "processing_dispatch_test's full 11-case suite passes under ctest (not just direct .exe invocation) in the SuperGenius submodule-consumption build"
    requirement: "TEST-01"
    verification:
      - kind: integration
        ref: "ctest --test-dir SuperGenius/build/Windows/Release -C Release -R processing_dispatch_test -V (11/11 passed, 0 failed)"
        status: pass
    human_judgment: false
  - id: D2
    description: "RenderPassEndToEndProducesVerifiedOutputHash's combinedHash is a genuine 32-byte, content-derived digest, not left empty by an outputs-less fixture"
    requirement: "TEST-01"
    verification:
      - kind: unit
        ref: "ProcessingDispatchTest.RenderPassEndToEndProducesVerifiedOutputHash [ OK ], ASSERT_EQ(hash.size(),32u) and ASSERT_NE(hash, all-zero) both genuinely exercised"
        status: pass
    human_judgment: false
  - id: D3
    description: "RenderPassSameNodeRepeatedExecutionProducesBitExactHash can no longer pass vacuously on all-empty hashes"
    requirement: "TEST-01"
    verification:
      - kind: unit
        ref: "processing_dispatch_test.cpp: ASSERT_EQ(iterHash.size(), 32u) added before each push_back in the 10-iteration loop; test still passes [ OK ] now against real non-empty hashes"
        status: pass
    human_judgment: false
  - id: D4
    description: "The ctest working-directory fix is scoped to processing_dispatch_test only; no other SuperGenius ctest target's working directory changes"
    requirement: "TEST-01"
    verification:
      - kind: integration
        ref: "grep confirms cmake/functions.cmake unmodified; full 13-target processing_-prefixed ctest sweep (ctest -R \"processing_\" -V) reports 13/13 passed, 0 failed"
        status: pass
    human_judgment: false

duration: 40min
completed: 2026-08-07
status: complete
---

# Phase 09 Plan 15: Processing Dispatch Test ctest/Hash Gap Closure Summary

**Fixed two independent, pre-existing bugs in `processing_dispatch_test`: a CTest working-directory mismatch that caused spurious GLSL `#version` errors on 4 sub-tests, and an empty `outputs: []` declaration on the happy-path render fixture that kept `combinedHash` perpetually empty — closing TEST-01's "full suite passes under ctest" gap and eliminating a vacuous-pass mode in the bit-exact repeat-run test.**

## Performance

- **Duration:** ~40 min
- **Tasks:** 3 (2 implementation, 1 verification-only regression sweep)
- **Files modified:** 3

## Accomplishments

- `processing_dispatch_test`'s CTest `WORKING_DIRECTORY` is now explicitly set to `$<TARGET_FILE_DIR:processing_dispatch_test>` via `set_tests_properties()`, matching where its GLSL/JSON fixtures are actually copied by the file's own `POST_BUILD` command — eliminating the "Desktop shaders for Vulkan SPIR-V require version 140" spurious failures that only occurred under `ctest`'s default source-tree-mirrored working directory, never under direct `.exe` invocation. Scoped to this one named target; `cmake/functions.cmake`'s shared `addtest()` helper (used by ~60 other targets) is untouched.
- `render-pass-happy-path-definition.json` now declares a real `outputs[0]` entry (`renderOutput`, mirroring `regression-b-parseblocksize-model-only.json`'s already-proven pattern), activating `ProcessingManager::Process()`'s existing (already-correct, unmodified) `!outputs.empty()`-gated artifact/manifest/`combinedHash` assembly block for this fixture for the first time since it was authored in Phase 03.
- `RenderPassSameNodeRepeatedExecutionProducesBitExactHash` now captures each iteration's hash into a named `iterHash` local and asserts `iterHash.size() == 32u` before pushing it into `allHashes`, closing the "10 equal-but-empty vectors pass vacuously" gap the debug session flagged. `RenderPassEndToEndProducesVerifiedOutputHash`'s pre-existing size/non-zero-sentinel assertions are unchanged but now genuinely exercised against a real hash instead of failing on an always-empty one.
- Full 11-case `processing_dispatch_test` suite passes cleanly under `ctest` (0 failures). Full 13-target `processing_`-prefixed ctest sweep (`processing_dispatch_test`, `processing_nodes_test`, `processing_schema_test`, `processing_datatypes_test`, `processing_result_durability_test`, `processing_validate_result_data_test`, and 7 `processing_conformance_*` suites) also reports 0 failures — confirming no regression from either fix.

## Task Commits

Each task was committed atomically at the correct submodule level per the phase-09 bump-pointer convention (these files live directly in the SuperGenius submodule, not in the nested SGProcessingManager submodule):

1. **Task 1: Scope processing_dispatch_test's ctest working directory** - `8ca2f191` (fix, SuperGenius submodule)
2. **Task 2: Declare real render output on happy-path fixture + strengthen repeat-run hash assertion** - `86b05687` (fix, SuperGenius submodule)
3. **Task 3: Full ctest regression sweep** - verification only, no file changes, no additional commit

Pointer bump: `7af71ad` (docs, GeniusNetwork parent repo — bumps SuperGenius submodule pointer to `8ca2f191`'s successor commit)

**Plan metadata:** (this commit, docs: complete plan)

## Files Created/Modified

- `SuperGenius/test/src/processing_dispatch/CMakeLists.txt` - Added `set_tests_properties( processing_dispatch_test PROPERTIES WORKING_DIRECTORY "$<TARGET_FILE_DIR:processing_dispatch_test>" )` immediately after the `addtest()` call
- `SuperGenius/test/src/processing_dispatch/render-pass-happy-path-definition.json` - Replaced empty `"outputs": []` with a single `renderOutput` entry pointing at `file://processing_dispatch/happy-path-render-output.raw`
- `SuperGenius/test/src/processing_dispatch/processing_dispatch_test.cpp` - `RenderPassSameNodeRepeatedExecutionProducesBitExactHash`: bound `process_result.value().combinedHash` to `iterHash`, added `ASSERT_EQ(iterHash.size(), 32u)` before `push_back`

## Decisions Made

- Used a target-scoped `set_tests_properties()` override rather than modifying the shared `addtest()` CMake helper, per the plan's explicit constraint — this guarantees none of the other ~60 SuperGenius ctest targets built through that helper have their working directory changed.
- Did not add `dimensions` or `format` fields to the new `outputs[0]` entry, matching the reference fixture (`regression-b-parseblocksize-model-only.json`) exactly and per the plan's explicit instruction — `ProcessingManager.cpp` derives `art.width`/`art.height`/`art.format` from the INPUT node metadata, not the output entry.
- Left `ProcessingManager.cpp`, `processing_processor_render.cpp`, and the `!outputs.empty()` gate itself completely untouched — both bugs were fixable entirely at the test-infrastructure/fixture layer, consistent with the plan's threat model disposition (both are pre-existing, already-correct production code paths).

## Deviations from Plan

None - plan executed exactly as written. All three tasks' acceptance criteria were met without needing any Rule 1-4 auto-fixes.

## Issues Encountered

None. The root cause for both Gap 2 ("Bug A", ctest working-directory mismatch) and Gap 3 ("Bug B", empty-outputs fixture) was already fully diagnosed in `.planning/debug/processing-dispatch-test-failure.md` prior to this plan, so implementation proceeded directly from that root-cause analysis. Both fixes worked on the first attempt with no rebuild/retry cycles needed beyond the expected incremental CMake reconfigure + rebuild.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Both Gap 2 and Gap 3 (TEST-01) are closed: `processing_dispatch_test`'s full 11-case suite now passes under `ctest` in the SuperGenius submodule-consumption build, matching its already-passing direct-`.exe`-invocation results.
- `RenderPassSameNodeRepeatedExecutionProducesBitExactHash` can no longer pass vacuously on empty hashes; it now independently proves each iteration produced a real 32-byte digest.
- Full 13-target `processing_`-prefixed ctest sweep confirms zero regressions outside `processing_dispatch_test` itself.
- This closes the last remaining gap-closure item for Phase 09 (processor-pass-graph-conformance-suites) noted in STATE.md ("09-15 remaining"). With this plan complete, Phase 09 has no further known open gaps against TEST-01.

---
*Phase: 09-processor-pass-graph-conformance-suites*
*Completed: 2026-08-07*

## Self-Check: PASSED

- FOUND: `SuperGenius/test/src/processing_dispatch/CMakeLists.txt`
- FOUND: `SuperGenius/test/src/processing_dispatch/render-pass-happy-path-definition.json`
- FOUND: `SuperGenius/test/src/processing_dispatch/processing_dispatch_test.cpp`
- FOUND: `8ca2f191` (SuperGenius submodule repo)
- FOUND: `86b05687` (SuperGenius submodule repo)
- FOUND: `7af71ad` (GeniusNetwork parent repo, pointer bump)
