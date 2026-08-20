---
phase: 17-render-path-cross-hardware-tolerance
plan: 06
subsystem: rendering
tags: [byteQuantMode, tolerance-derivation, secv01, counter-test, vulkan, quantization]

requires:
  - phase: 17-05
    provides: 17-CAPTURE-RESULTS-ROUND1.md's real per-fixture maxAbsDelta (lighting 0.0, blending 1.0) as the binary search's starting point
provides:
  - Empirically-derived, counter-test-proven byteQuantMode values for lighting (N=5) and blending (N=6)
  - Two new dedicated SECV-01-style counter-tests (secv01_render_lighting_counter_test.cpp, secv01_render_blending_counter_test.cpp)
  - A fixed push-constant field-order bug in lighting_fragment_shader.glsl that had made the lighting fixture render a degenerate solid-black image regardless of lightColor
affects: [17-07 (texturing's own byteQuantMode derivation), 17-08 (Round 2 verification -- must include a fresh lighting capture against the now-corrected shader)]

tech-stack:
  added: []
  patterns: [binary-search-against-a-counter-test tolerance derivation (Phase 13/14 precedent, applied per-fixture to byteQuantMode's discrete N in [0,8], increasing-N-is-more-tolerant direction]

key-files:
  created:
    - SuperGenius/test/src/processing_conformance_security/secv01_render_lighting_counter_test.cpp
    - SuperGenius/test/src/processing_conformance_security/secv01_render_blending_counter_test.cpp
  modified:
    - SuperGenius/test/src/processing_conformance_security/CMakeLists.txt
    - SuperGenius/test/src/processing_dispatch/CMakeLists.txt
    - SuperGenius/test/src/processing_dispatch/lighting-fixture-definition.json
    - SuperGenius/test/src/processing_dispatch/lighting_fragment_shader.glsl
    - SuperGenius/test/src/processing_dispatch/blending-fixture-definition.json

decisions:
  - "Lighting's byteQuantMode=5: binary search over N in [0,8] against LightingWrongColorStillDiverges found the counter-test passes through N=5 and fails (artifactIds collide, confirmed deterministic twice) at N=6 -- N=5 chosen one step below that boundary. Because the real 17-CAPTURE-RESULTS-ROUND1.md maxAbsDelta=0.0 figure for lighting is now known to reflect a degenerate solid-black render (see the push-constant bug below), N=5 is honestly reported as derived purely from the counter-test's own corruption-detection boundary, not from a fresh real-divergence measurement against the corrected shader."
  - "Blending's byteQuantMode=6: binary search over N in [1,8] (starting floor from the real maxAbsDelta=1.0) against BlendingWrongFactorStillDiverges found the counter-test passes through N=6 and fails at N=7 -- N=6 chosen one step below that boundary, giving a ~64x margin over the real measured divergence."
  - "[Rule 1 - Bug] Fixed a push-constant field-order bug in lighting_fragment_shader.glsl found while writing lighting's own counter-test at byteQuantMode=0 (raw byte-identity): the shader's push_constant struct declared lightDir/lightColor/viewPos in that literal order, but RenderProcessor::ResolveUniforms packs uniforms in std::map key-SORTED (alphabetical) order -- lightColor/lightDir/viewPos. The mismatch silently swapped lightColor's and lightDir's bytes at the shader boundary. Because normalize() erases uniform scaling, [1,1,1] and [0.5,0.5,0.5] normalize to the identical direction once misread as lightDir, making the deliberate corruption completely invisible at ANY byteQuantMode -- and independently explains why 17-05's Round 1 capture measured 'zero divergence' for lighting (confirmed via lighting-render-output.raw: every pixel byte was exactly 0x00/0x00/0x00/0xFF, a degenerate constant, not real per-fragment Phong math). Fixed by reordering the push-constant struct to the alphabetical order that actually matches ResolveUniforms's packing convention."
  - "[Rule 3 - Blocking] lighting-fixture-definition.json/blending-fixture-definition.json and their shader/vertex-data files were authored in 17-01/17-02 but never added to processing_dispatch/CMakeLists.txt's POST_BUILD copy list -- meaning the shared test_bin/processing_dispatch/ directory (all test binaries share one RUNTIME_OUTPUT_DIRECTORY, per cmake/functions.cmake's addtest()) never actually contained these fixtures' files, so any GTest binary referencing them via file://processing_dispatch/... would fail with 'Failed to open file'. Added all 8 missing lighting/blending files to the copy list (this task's two counter-tests are the first GTest consumers of these fixtures) so both counter-tests can resolve their file:// URIs."

requirements-completed: []

coverage:
  - id: D1
    description: "Lighting's byteQuantMode is derived independently via binary-search-against-a-counter-test (D-06), starting from 17-CAPTURE-RESULTS-ROUND1.md's real maxAbsDelta=0.0, never guessed a priori"
    requirement: "RENDTOL-02"
    verification:
      - kind: automated_test
        ref: "ctest -R Secv01RenderLightingCounterTest (via direct --gtest_filter invocation, ctest's per-target granularity does not expose individual TEST_F names) -- 100% passed at N=5; N=6 confirmed to deterministically fail (re-run twice) before selecting N=5"
        status: pass
    human_judgment: false
  - id: D2
    description: "Blending's byteQuantMode is derived independently via binary-search-against-a-counter-test (D-06), starting from 17-CAPTURE-RESULTS-ROUND1.md's real maxAbsDelta=1.0"
    requirement: "RENDTOL-02"
    verification:
      - kind: automated_test
        ref: "Secv01RenderBlendingCounterTest.BlendingWrongFactorStillDiverges -- 100% passed at N=6; N=7 confirmed to deterministically fail (re-run twice) before selecting N=6"
        status: pass
    human_judgment: false
  - id: D3
    description: "Each fixture gets its own dedicated counter-test file (D-07), mirroring secv01_tex3d_counter_test.cpp's per-fixture-file precedent"
    requirement: "RENDTOL-02"
    verification:
      - kind: other
        ref: "Two new files: secv01_render_lighting_counter_test.cpp, secv01_render_blending_counter_test.cpp, both registered in processing_conformance_security_test's CMake target alongside the three pre-existing sources"
        status: pass
    human_judgment: false
  - id: D4
    description: "Production fixture JSON and counter-test inline JSON agree exactly on the final chosen byteQuantMode value, with a citation-trail description in the production JSON"
    requirement: "RENDTOL-02"
    verification:
      - kind: other
        ref: "lighting-fixture-definition.json parameters[0].default=5 matches both of secv01_render_lighting_counter_test.cpp's inline JSON literals; blending-fixture-definition.json parameters[0].default=6 matches both of secv01_render_blending_counter_test.cpp's inline JSON literals. Both descriptions cite the real numeric maxAbsDelta from 17-CAPTURE-RESULTS-ROUND1.md."
        status: pass
    human_judgment: false

duration: 90min
completed: 2026-08-19
status: complete
---

# Phase 17 Plan 06: Lighting and Blending byteQuantMode Derivation Summary

**Lighting's byteQuantMode=5 and blending's byteQuantMode=6, each empirically derived via binary search against a dedicated new SECV-01-style counter-test -- and a real push-constant field-order bug in the lighting shader (found while writing its counter-test) fixed along the way, which also retroactively explains 17-05's "zero divergence" finding for lighting as a degenerate solid-black render, not genuine Phong lighting.**

## Performance

- **Duration:** ~90 min
- **Completed:** 2026-08-19
- **Tasks:** 2
- **Files modified:** 7 (2 new counter-test files, 2 CMakeLists.txt, 2 fixture JSON, 1 shader bugfix)

## Accomplishments

- Wrote `secv01_render_lighting_counter_test.cpp` (`Secv01RenderLightingCounterTest.LightingWrongColorStillDiverges`), mirroring `secv01_tex3d_counter_test.cpp`'s per-fixture-file structure and `secv01_counter_test.cpp::RenderWrongShaderConstantStillDiverges`'s render-job/`ModelNode`/`Process()` shape.
- While proving this counter-test at the divergence-absorption floor (N=0), discovered the correct and deliberately-wrong-lightColor jobs produced a **bit-identical** artifactId even with **zero quantization** -- root-caused to a push-constant field-order mismatch between `lighting_fragment_shader.glsl`'s declared struct order and `RenderProcessor::ResolveUniforms`'s alphabetical `std::map`-based packing order. Fixed the shader (Rule 1), which also explains why 17-05's Round 1 capture measured zero cross-hardware divergence for lighting: the fixture had been rendering a degenerate solid-black image (`lighting-render-output.raw` confirmed every byte exactly `0x00/0x00/0x00/0xFF`), not real per-fragment Phong lighting.
- Ran a real, rebuild-and-run binary search (not a table lookup) over `byteQuantMode` N in `[0,8]` against the corrected counter-test: passes through N=5, fails deterministically at N=6 (re-confirmed twice) -- final value N=5.
- Wrote `secv01_render_blending_counter_test.cpp` (`Secv01RenderBlendingCounterTest.BlendingWrongFactorStillDiverges`), asserting a deliberately wrong blend factor pair (`one`/`zero` instead of `src_alpha`/`one_minus_src_alpha`) still diverges post-quantization.
- Ran the same binary-search discipline for blending, starting from the real captured `maxAbsDelta=1.0` floor (N=1): passes through N=6, fails deterministically at N=7 (re-confirmed twice) -- final value N=6.
- Found and fixed a Rule 3 blocking gap: `lighting-fixture-definition.json`/`blending-fixture-definition.json` and their shader/vertex-data files (authored in 17-01/17-02) had never been added to `processing_dispatch/CMakeLists.txt`'s POST_BUILD copy list, so no GTest binary could ever resolve their `file://processing_dispatch/...` URIs. Added all 8 missing files so both new counter-tests (the first GTest consumers of these fixtures) can build and run.
- Wired both final values into their production fixture JSON's new `parameters` array, each with a citation-trail description mirroring `13-04-PLAN.md`/`texture3d-processing-definition.json`'s convention.
- Verified the full `processing_conformance_security_test` suite (6/6) and the broader `processing|render|capture|dispatch`-scoped ctest run (19/19, 1 pre-existing unrelated skip) still pass after all changes.

## Task Commits

Each task was committed atomically (submodule-first, then outer-repo pointer bump, per this project's convention):

1. **Task 1: Derive lighting's byteQuantMode and write its counter-test** - `2694889d` (SuperGenius submodule, feat)
2. **Task 2: Derive blending's byteQuantMode and write its counter-test** - `b3989cde` (SuperGenius submodule, feat)
3. Outer-repo submodule pointer bump - `a5a1335` (chore)

**Plan metadata:** (this commit) `docs(17-06): complete plan`

## Files Created/Modified

- `SuperGenius/test/src/processing_conformance_security/secv01_render_lighting_counter_test.cpp` - new SECV-01-style counter-test, `LightingWrongColorStillDiverges`
- `SuperGenius/test/src/processing_conformance_security/secv01_render_blending_counter_test.cpp` - new SECV-01-style counter-test, `BlendingWrongFactorStillDiverges`
- `SuperGenius/test/src/processing_conformance_security/CMakeLists.txt` - registered both new sources in `processing_conformance_security_test`
- `SuperGenius/test/src/processing_dispatch/CMakeLists.txt` - added 8 missing lighting/blending fixture files to the POST_BUILD copy list
- `SuperGenius/test/src/processing_dispatch/lighting-fixture-definition.json` - added `parameters: [{byteQuantMode: 5}]` with citation-trail description
- `SuperGenius/test/src/processing_dispatch/lighting_fragment_shader.glsl` - fixed push-constant struct member order (lightColor/lightDir/viewPos, matching `ResolveUniforms`'s alphabetical packing)
- `SuperGenius/test/src/processing_dispatch/blending-fixture-definition.json` - added `parameters: [{byteQuantMode: 6}]` with citation-trail description

## Decisions Made

- Lighting's byteQuantMode=5 (binary search boundary at N=6), honestly reported as derived from the counter-test's own corruption-detection boundary rather than fresh real-divergence data, since the shader bug fix invalidates 17-05's original zero-divergence measurement for lighting.
- Blending's byteQuantMode=6 (binary search boundary at N=7), ~64x margin over the real captured `maxAbsDelta=1.0`.
- Fixed the lighting push-constant field-order bug in the shader itself (alphabetical reorder) rather than changing `ResolveUniforms`'s packing convention, keeping the fix self-contained to this fixture and avoiding any change to shared `RenderProcessor` production code or the already-established `SerializeRenderPassConfig`/`ParseRenderPassConfig` wire-format convention (DETV-01).
- Did not re-run `requirements.mark-complete` for RENDTOL-02 -- it is already (prematurely) marked Complete in REQUIREMENTS.md as of Plan 17-02, a known STATE.md-tracked discrepancy explicitly flagged for revisit at phase close (17-05 made the same call for the same reason).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed lighting_fragment_shader.glsl's push-constant field-order mismatch**
- **Found during:** Task 1, while proving `LightingWrongColorStillDiverges` at byteQuantMode=0 (raw byte-identity)
- **Issue:** The shader's `push_constant` struct declared `lightDir`/`lightColor`/`viewPos` in "natural" order, but `RenderProcessor::ResolveUniforms` packs each `render_shader.uniforms` entry in `std::map` key-SORTED (alphabetical: `lightColor`/`lightDir`/`viewPos`) order -- an intentional, documented determinism choice (DETV-01) that assumes shader authors declare their struct in matching order. The mismatch meant the shader read `lightColor`'s bytes into `u.lightDir` and vice versa. Since `normalize()` erases uniform scaling, `[1,1,1]` and `[0.5,0.5,0.5]` (parallel vectors) normalized to the identical direction once misread as a direction, making the deliberate lightColor corruption completely undetectable at ANY byteQuantMode -- confirmed via direct instrumentation of `QuantizeByteBuffer` showing both jobs producing bit-identical post-quantization buffers even at N=0 (no masking at all).
- **Fix:** Reordered the push-constant struct to `lightColor`/`lightDir`/`viewPos`, matching `ResolveUniforms`'s actual packing order, with an inline comment documenting the convention and this finding for future shader authors.
- **Files modified:** `SuperGenius/test/src/processing_dispatch/lighting_fragment_shader.glsl`
- **Verification:** After the fix, `LightingWrongColorStillDiverges` passes at N=0 through N=5 and fails deterministically at N=6 (confirmed by two separate re-runs), proving the fixture now actually exercises real per-fragment Phong lighting math driven by its declared uniforms.
- **Committed in:** `2694889d`
- **Significant downstream implication (flagged, not fixed by this plan):** `17-CAPTURE-RESULTS-ROUND1.md`'s lighting entry (`maxAbsDelta=0.0`, `contentHashMatch=true`) reflects the pre-fix degenerate solid-black render, not genuine cross-hardware Phong-lighting divergence. That document's historical record is left untouched (it accurately reports what Round 1 actually measured), but a fresh capture of the corrected shader is now a real, outstanding prerequisite for the phase's Round 2 verification (17-08) to be meaningful for the lighting fixture -- Round 2 must not assume lighting's "zero divergence" still holds for the corrected shader.

**2. [Rule 3 - Blocking] Added 8 missing lighting/blending fixture files to processing_dispatch/CMakeLists.txt's copy list**
- **Found during:** Task 1, first build+run attempt of the new counter-test
- **Issue:** All test binaries in this project share one `RUNTIME_OUTPUT_DIRECTORY` (`test_bin/`, per `cmake/functions.cmake`'s `addtest()`), and cross-test-binary fixture sharing depends on each fixture's owning `CMakeLists.txt` copying its files into that shared directory (`processing_dispatch/` subfolder). `lighting-fixture-definition.json`/`blending-fixture-definition.json` and their shader/vertex-data files (authored in 17-01/17-02) were never added to this copy list -- they had only ever been consumed directly from source by `capture_harness` (a separate CLI tool, not a ctest target), so this gap was invisible until this plan's counter-tests became the first GTest consumers.
- **Fix:** Added `lighting-fixture-definition.json`, `lighting_vertex_shader.glsl`, `lighting_fragment_shader.glsl`, `lighting-vertex-data.raw`, `blending-fixture-definition.json`, `blending_vertex_shader.glsl`, `blending_fragment_shader.glsl`, `blending-vertex-data.raw` to `processing_dispatch/CMakeLists.txt`'s POST_BUILD copy command.
- **Files modified:** `SuperGenius/test/src/processing_dispatch/CMakeLists.txt`
- **Verification:** Both new counter-tests build and their `file://processing_dispatch/...` URIs resolve correctly after rebuilding `processing_dispatch_test` (whose POST_BUILD step performs the actual copy).
- **Committed in:** `2694889d` (lighting's 4 files), `b3989cde` (blending's 4 files)

---

**Total deviations:** 2 auto-fixed (1 bug, 1 blocking gap)
**Impact on plan:** No scope creep in terms of new features -- both fixes were strictly necessary to make this plan's own counter-tests buildable and meaningful. The shader bug fix has a real downstream implication (flagged above) for a future re-capture, but does not block or alter this plan's own deliverables (both counter-tests pass with real, empirically-derived byteQuantMode values).

## Issues Encountered

- Lighting's byteQuantMode=5 is honestly NOT yet verified against fresh real cross-hardware divergence data for the corrected shader (only against this counter-test's own corruption-detection boundary) -- 17-CAPTURE-RESULTS-ROUND1.md's original `maxAbsDelta=0.0` for lighting is now known-stale. Flagged for whoever runs Round 2 (17-08).
- An initial loop-based binary search attempt for lighting silently ran against a stale compiled binary for one iteration (a `sed`+incremental-rebuild timing quirk); caught by re-verifying with explicit recompile-detection checks (`grep -c` on the build log for the changed source file) before trusting any pass/fail result. All final N=5/N=6 boundary claims in this summary were confirmed via builds that visibly recompiled the changed test file, and each boundary was re-run twice for determinism.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Texturing's own `byteQuantMode` derivation (17-07) remains pending and is unaffected by this plan's work (texturing has no lighting-style uniform-wiring dependency).
- Round 2 verification (17-08) is still pending for all three fixtures. For lighting specifically, Round 2 must capture FRESH real cross-hardware data against the corrected shader -- the old Round 1 "zero divergence" figure for lighting no longer describes real Phong-lighting behavior and must not be reused or assumed to still hold.
- REQUIREMENTS.md's RENDTOL-01/02 premature-completion discrepancy (flagged since Plan 17-02, re-flagged in 17-05) remains open for revisit at phase close -- this plan did not re-run `requirements.mark-complete`, consistent with 17-05's own decision.

---
*Phase: 17-render-path-cross-hardware-tolerance*
*Completed: 2026-08-19*
