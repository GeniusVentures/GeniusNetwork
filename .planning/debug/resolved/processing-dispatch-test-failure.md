---
status: resolved
trigger: "As far as SuperGenius procesing_ tests, only processing_dispatch_test is failing, which i'm not sure if that is part of this phase, but should be addressed."
created: 2026-08-06T00:00:00Z
updated: 2026-08-07T03:32:05.000Z
---

## Current Focus

hypothesis: CONFIRMED (two distinct, independent, pre-Phase-09 bugs — see Resolution). Investigation complete.
test: n/a — investigation complete.
expecting: n/a
next_action: n/a — root cause found, reporting to caller (goal: find_root_cause_only, no fix applied).

## Symptoms

expected: |
  ctest passes with the same results in both the standalone SGProcessingManager
  build and the SuperGenius/develop submodule-consumption build, per roadmap
  Success Criterion 1 (TEST-01) for phase 09 (processor-pass-graph-conformance-suites).
  Among SuperGenius's "processing_" prefixed test targets, all should pass;
  processing_dispatch_test is the one currently failing.
actual: |
  processing_dispatch_test fails in the SuperGenius build. It is the only
  processing_-prefixed test failing there. User is uncertain whether this test
  is in scope for phase 09 (it may be validating pre-existing SuperGenius
  dispatch behavior rather than the new processor pass graph conformance work),
  but flags it should be investigated and addressed regardless.

  A sibling debug session (capability-validator-reject-unregistered) that just
  completed noted in passing, without independently investigating: "the
  UAT/verification docs also flag processing_dispatch_test as failing in the
  SuperGenius build (4 pre-existing GLSL #version failures per
  09-VERIFICATION.md, traced to Phase 08 commit 47bd0bd8) — a separate,
  already-disclosed issue." Treat this as a lead to verify, not a confirmed
  conclusion — confirm it independently against the actual current test output
  and the cited verification doc/commit before accepting it.
errors: "None reported verbatim by user — need to run test directly to capture actual gtest failure output."
reproduction: "Build and run ctest for SuperGenius, target processing_dispatch_test. Test file: SuperGenius/test/src/processing_dispatch/processing_dispatch_test.cpp"
started: "Discovered during UAT for phase 09"

## Eliminated

- hypothesis: "The '4 GLSL #version failures' claim from 09-VERIFICATION.md is simply wrong/hallucinated, since running the .exe directly only shows 1 failure."
  evidence: "Running the pre-built .exe directly from its own directory (test_bin/Release/) with cwd=that directory produces only 1 failure (RenderPassEndToEndProducesVerifiedOutputHash, hash.size()==0). But running the SAME binary via `ctest -C Release -R processing_dispatch_test -V` (cwd set by CMake's default add_test() behavior to build/Windows/Release/test/src/processing_dispatch) reproduces exactly the claimed '7 passed, 4 failed' with the identical GLSL #version symptom. The claim was accurate for the ctest invocation path — verified independently, not hallucinated."
  timestamp: 2026-08-06T22:10:00Z

## Evidence

- timestamp: 2026-08-06T22:07:00Z
  checked: "Ran w:/gnus/GeniusNetwork/SuperGenius/build/Windows/Release/test_bin/Release/processing_dispatch_test.exe directly (cwd = its own dir)"
  found: "11 tests run, 10 PASSED, 1 FAILED: ProcessingDispatchTest.RenderPassEndToEndProducesVerifiedOutputHash — `ASSERT_EQ(hash.size(), 32u)` fails, hash.size() is 0. Process() itself succeeded (has_value()==true); the render pipeline genuinely ran (saw real Progress: pass=renderInput percent=25/50/75/100 events). Reproduced 3x via --gtest_repeat=3, 100% consistent, not flaky."
  implication: "When cwd is correct (matches binary's own directory), the shader-loading/dispatch machinery works fine. The only failure is that ProcessOutput.combinedHash ends up empty even though Process() succeeded — a distinct bug from any GLSL/#version issue."

- timestamp: 2026-08-06T22:09:00Z
  checked: "Ran `ctest -C Release -R processing_dispatch_test -V` from build/Windows/Release (cwd forced by CMake's default add_test() WORKING_DIRECTORY, which is build/Windows/Release/test/src/processing_dispatch — NOT the binary's own directory)"
  found: "11 tests run, 7 PASSED, 4 FAILED: RenderPassValidGlslShadersCompileAndValidateEndToEnd, RenderPassStillFailsCleanlyOnMissingRenderInputAfterFullWiring, RenderPassSameNodeRepeatedExecutionProducesBitExactHash, RenderPassEndToEndProducesVerifiedOutputHash. All 4 preceded by '[error][FILECommon] Failed to open file (Windows): The system cannot find the path specified' (x3) then '[error][ShaderCompiler] ShaderCompiler: GLSL compile failed: shader: error: #version: Desktop shaders for Vulkan SPIR-V require version 140 or higher'. This exactly matches 09-VERIFICATION.md's claimed '7 passed, 4 failed' with 'GLSL #version symptom'."
  implication: "The GLSL #version failures are caused by the file://processing_dispatch/*.glsl fixture URLs failing to resolve when cwd != the binary's own directory (i.e. under ctest's default working directory), not by any real GLSL syntax problem. This is a working-directory-relative fixture-path resolution bug, invocation-method-dependent."

- timestamp: 2026-08-06T22:11:00Z
  checked: ".planning/workstreams/sgproc-render/phases/03-renderprocessor-implementation-determinism/deferred-items.md (DI-03-01-01)"
  found: "This EXACT symptom (byte-for-byte: same log lines 'Failed to obtain processing source: File could not be opened' x3, 'FILECommon: Failed to open file (Windows)...', 'GLSL compile failed: shader: error: #version: Desktop shaders for Vulkan SPIR-V require version 140 or higher') was already discovered, documented, and explicitly DEFERRED during Phase 03 plan 03-01 — over a month before Phase 08 or Phase 09 existed. The doc's own root-cause hypothesis: 'A working-directory-relative fixture-path resolution gap in the test's file:// URL fetch path.' The doc also states it was confirmed present on 'dev_rendering's prior HEAD' by stashing changes and re-running — i.e. pre-existing before plan 03-01 even started."
  implication: "Bug A (the 4 GLSL #version ctest failures) is a Phase-03-origin, already-disclosed, already-deferred defect. It has nothing to do with Phase 08's 47bd0bd8 commit (which only mechanically changed `.value()` -> `.value().combinedHash` accessors) or any Phase 09 work. 09-VERIFICATION.md's git-blame attribution to 47bd0bd8 is technically true (last commit touching the file) but causally misleading — the actual root cause long predates that commit."

- timestamp: 2026-08-06T22:15:00Z
  checked: "SuperGenius/test/src/processing_dispatch/render-pass-happy-path-definition.json (fixture used by RenderPassEndToEndProducesVerifiedOutputHash and RenderPassSameNodeRepeatedExecutionProducesBitExactHash)"
  found: "Fixture declares `\"outputs\": []` (empty array) — has never had a non-empty outputs list since it was created by commit 1a22674f 'feat(03-06): add new happy-path render fixture' (Phase 03). Never modified since."
  implication: "Any code path in ProcessingManager::Process() that gates on `!outputs.empty()` will never execute for this fixture."

- timestamp: 2026-08-06T22:16:00Z
  checked: "SGProcessingManager/src/processingbase/ProcessingManager.cpp lines ~1360-1511 (ProcessOutput/artifact/manifest/combinedHash assembly block) and its git line-history (`git log -L 1365,1366:...`)"
  found: "The gating condition `if ( processResult.output_buffers && !outputs.empty() )` wraps ALL artifact-building, ExecutionManifest assembly, AND the `output.combinedHash = mHash;` assignment (line 1510). This gate was introduced by SGProcessingManager submodule commit b9c445b 'Phase 08: Structured Artifacts & Execution Manifests -- type system, binary serialization, Process() integration' (2026-08-05). Phase 09's only touch to this same block (09-11, commit c6f993e 'fix(09-11): default BUFFER-input artifact format to INT8 instead of crashing') changed only the format-defaulting sub-block (get_format().value_or(...)) a few lines below the gate — it did not touch the `!outputs.empty()` condition itself."
  implication: "Bug B (combinedHash.size()==0 for the happy-path fixture) was introduced by Phase 08's ProcessOutput refactor interacting with a Phase-03-era fixture that has always had empty 'outputs'. Phase 09 did not introduce, alter, or touch this gate. This is a previously UNDISCLOSED regression from Phase 08 (not covered by DI-03-01-01, which is about the unrelated file:// path-resolution issue)."

- timestamp: 2026-08-06T22:17:00Z
  checked: "RenderPassSameNodeRepeatedExecutionProducesBitExactHash test body (lines 266-313) — whether it independently validates hash.size()==32"
  found: "This test ONLY asserts `allHashes[i] == allHashes[0]` across 10 iterations; it never independently asserts a non-empty/32-byte hash. If combinedHash is empty for every iteration (as Bug B causes), all 10 empty vectors trivially compare equal and the test PASSES vacuously — masking Bug B entirely under direct .exe invocation."
  implication: "This test currently provides a false sense of security for the DETV-01 bit-exact-repeat-run claim: it would keep passing even if combinedHash were permanently broken/empty, because it never checks the hash is actually populated."

- timestamp: 2026-08-06T22:18:00Z
  checked: "Full ctest sweep of all 13 'processing_'-prefixed ctest targets: `ctest -C Release -R \"processing_\"`"
  found: "12/13 passed; only processing_dispatch_test failed (4 sub-cases, same GLSL #version/Bug-A symptom under ctest's cwd). All 7 processing_conformance_* suites (Phase 09's newly-authored suites) and processing_datatypes_test, processing_nodes_test, processing_schema_test, processing_result_durability_test, processing_validate_result_data_test all passed cleanly."
  implication: "Confirms the user's own observation exactly: processing_dispatch_test is the ONLY processing_-prefixed ctest target failing. None of Phase 09's own conformance suites are affected by either Bug A or Bug B, because they don't use the file://-URI-based fixture-loading mechanism (Bug A) and none of their fixtures declare empty 'outputs' arrays for a render pass whose result is hash-checked (Bug B)."

- timestamp: 2026-08-06T22:19:00Z
  checked: "SuperGenius git submodule status/log (`git status --short`, `git log --oneline -5`) to check for inconsistent/dirty submodule state before drawing conclusions"
  found: "Clean except for untracked test-run artifacts (first_patch_input.raw, first_patch_output.raw, stitched_logits.raw, test/src/processing_datatypes/.gitignore) — no modified tracked files, no detached-HEAD/stale-pointer anomaly. HEAD is 95e46966 (09-13's pointer bump), consistent with the phase's latest work."
  implication: "Submodule state is consistent; investigation results are not confounded by a stale or dirty checkout."

## Resolution

root_cause: |
  TWO independent, pre-existing bugs both surface as "processing_dispatch_test fails," neither
  caused by, related to, or touched by Phase 09 (processor-pass-graph-conformance-suites) work:

  BUG A (the "4 GLSL #version failures" cited in 09-VERIFICATION.md) — Phase 03 origin, already
  disclosed and deferred (see DI-03-01-01 in
  .planning/workstreams/sgproc-render/phases/03-renderprocessor-implementation-determinism/deferred-items.md):
  a working-directory-relative fixture-path resolution gap in the test's `file://processing_dispatch/*`
  URL fetch mechanism. The fixture GLSL/JSON files are copied next to the test binary
  (test_bin/Release/processing_dispatch/), and JSON loading (LoadJson(), via
  boost::dll::program_location()) is unaffected by cwd — but the `file://` URI resolver used to
  fetch shader source bytes referenced *inside* the JSON appears to resolve relative to the
  process's current working directory, not the binary's location. CMake's `addtest()` helper
  (SuperGenius/cmake/functions.cmake) calls `add_test()` without an explicit WORKING_DIRECTORY,
  so CTest defaults cwd to build/Windows/Release/test/src/processing_dispatch (mirroring the
  *source* tree location), which has no `processing_dispatch/` fixture subfolder. Under that cwd,
  shader-source fetches fail ("Failed to open file... path specified"), an empty buffer reaches
  shaderc, and shaderc reports a spurious "#version: Desktop shaders... require version 140"
  error (since the empty buffer has no #version directive) instead of the real GLSL syntax. This
  exact symptom was discovered and deferred during Phase 03 plan 03-01, confirmed present even on
  dev_rendering's prior HEAD before that plan's own changes — i.e., genuinely pre-existing, and
  untouched by any Phase 08 or Phase 09 commit. 09-VERIFICATION.md's attribution to Phase 08 commit
  47bd0bd8 is technically accurate only as "last commit that touched the test file" (a 2-line
  `.value()` -> `.value().combinedHash` API-adaptation edit) but is causally misleading: 47bd0bd8
  did not introduce, alter, or interact with this working-directory bug in any way.

  BUG B (newly discovered by this investigation, NOT previously disclosed anywhere) — Phase 08
  origin: ProcessingManager::Process()'s ProcessOutput-assembly block
  (SGProcessingManager/src/processingbase/ProcessingManager.cpp, introduced by submodule commit
  b9c445b "Phase 08: Structured Artifacts & Execution Manifests") gates ALL artifact/manifest/
  combinedHash population behind `if ( processResult.output_buffers && !outputs.empty() )`. The
  happy-path render fixture used by RenderPassEndToEndProducesVerifiedOutputHash and
  RenderPassSameNodeRepeatedExecutionProducesBitExactHash
  (test/src/processing_dispatch/render-pass-happy-path-definition.json, created by Phase-03 commit
  1a22674f, never modified since) declares `"outputs": []` — it has always had zero declared
  outputs, because the "outputs" schema concept and the ProcessOutput/combinedHash mechanism did
  not exist yet when this fixture was authored in Phase 03/04. When Phase 08 introduced this gate
  and mechanically retargeted the test's hash access to `.combinedHash` (47bd0bd8), nobody updated
  the fixture to declare an output entry, so the gate never fires for this render pass:
  `output.combinedHash` stays default-constructed (empty, size 0) even though Process() genuinely
  succeeds and the render pipeline genuinely executes end-to-end. This is why, when the test binary
  is run with a CORRECT working directory (bypassing Bug A entirely), 10/11 sub-tests pass but
  RenderPassEndToEndProducesVerifiedOutputHash still fails on `ASSERT_EQ(hash.size(), 32u)`.
  RenderPassSameNodeRepeatedExecutionProducesBitExactHash does NOT independently check hash.size(),
  only that its 10 iterations' hashes match each other — so it passes vacuously (comparing 10 empty
  vectors to each other) and silently masks Bug B under direct .exe invocation. Phase 09 did not
  touch the `!outputs.empty()` gate (confirmed via `git log -L` on that exact line); Phase 09's only
  edit in this same code block (09-11 / commit c6f993e) touched only the unrelated format-defaulting
  sub-block several lines below the gate.

  SCOPE DETERMINATION: Both bugs are pre-existing and unrelated to Phase 09
  (processor-pass-graph-conformance-suites). Phase 09 added 7 new processing_conformance_* ctest
  targets and made small, unrelated fixes to ProcessingManager.cpp (BUFFER-format defaulting,
  5-arg ExecutionContext overload) — none of which created, worsened, or interacted with either
  bug. processing_dispatch_test is a legacy Phase 01-04 test file that Phase 08 mechanically
  adapted for its new ProcessOutput API; it is not one of Phase 09's own conformance suites. This
  matches and confirms the user's own uncertainty ("not sure if that is part of this phase") —
  it is NOT part of Phase 09's deliverables, but both bugs are real, currently-failing defects
  that should be tracked and fixed as their own (pre-Phase-09) work items, ideally before Phase 09
  is considered fully closed against its "ctest passes" roadmap success criterion (TEST-01), since
  TEST-01 is phrased in terms of the whole suite passing under `ctest`, and processing_dispatch_test
  is part of that suite.
fix: ""
verification: ""
files_changed: []
