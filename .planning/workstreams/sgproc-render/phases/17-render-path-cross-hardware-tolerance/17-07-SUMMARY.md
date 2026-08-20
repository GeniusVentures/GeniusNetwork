---
phase: 17-render-path-cross-hardware-tolerance
plan: 07
subsystem: rendering
tags: [byteQuantMode, tolerance-derivation, secv01, counter-test, vulkan, quantization, texturing]

requires:
  - phase: 17-05
    provides: 17-CAPTURE-RESULTS-ROUND1.md's real per-fixture maxAbsDelta (texturing 0.0) as the binary search's starting point
  - phase: 17-06
    provides: the exact secv01_render_*_counter_test.cpp structural template (Secv01RenderLightingCounterTest/Secv01RenderBlendingCounterTest) and the processing_dispatch/CMakeLists.txt missing-fixture-copy fix precedent this plan repeats for texturing's own files
provides:
  - Empirically-derived, counter-test-proven byteQuantMode value for texturing (N=7) -- RENDTOL-02's derivation now complete for all three fixtures (lighting=5, blending=6, texturing=7)
  - A new dedicated SECV-01-style counter-test (secv01_render_texturing_counter_test.cpp) whose "wrong" variant substitutes a fully bit-inverted corrupted source texture image
  - A 16384-byte fully bit-inverted corrupted texture asset (secv01-wrong-texture-source-image.raw)
affects: [17-08 (Round 2 verification -- must capture fresh real cross-hardware divergence for texturing against byteQuantMode=7, same as lighting needs a fresh capture per 17-06)]

tech-stack:
  added: []
  patterns: [binary-search-against-a-counter-test tolerance derivation (Phase 13/14 precedent, applied per-fixture to byteQuantMode's discrete N in [0,8], increasing-N-is-more-tolerant direction), full bit-inversion as the maximal-divergence "wrong" variant for a raw unstructured RGBA8 buffer (no parseable structure to accidentally break, unlike a .mnn model)]

key-files:
  created:
    - SuperGenius/test/src/processing_conformance_security/secv01_render_texturing_counter_test.cpp
    - SuperGenius/test/src/processing_conformance_security/fixtures/secv01-wrong-texture-source-image.raw
  modified:
    - SuperGenius/test/src/processing_conformance_security/CMakeLists.txt
    - SuperGenius/test/src/processing_dispatch/CMakeLists.txt
    - SuperGenius/test/src/processing_dispatch/texturing-fixture-definition.json

decisions:
  - "Texturing's byteQuantMode=7: binary search over N in [0,8] against TexturingWrongSourceImageStillDiverges found N=0 through N=7 all still detect a fully bit-inverted corrupted source texture, and N=8 fails (every byte quantizes to 0x00 regardless of input -- an expected degenerate edge case anticipated by RESEARCH.md's Tolerance Derivation Methodology step 4, not a surprise). N=7 was chosen one integer step below that N=8 failure boundary, and both N=7 (pass) and N=8 (fail) were re-confirmed deterministic via two independent re-runs each."
  - "Because 17-CAPTURE-RESULTS-ROUND1.md's real measured maxAbsDelta for texturing is genuinely 0.0 (not a stale/degenerate figure the way lighting's turned out to be in 17-06 -- confirmed below), N=7 is honestly reported as derived purely from this counter-test's own corruption-detection boundary, not from margining above a non-zero real divergence figure -- an explicit, documented D-08 case."
  - "Confirmed texturing's zero-divergence result is NOT a hidden bug the way lighting's was: this counter-test's own fully bit-inverted corrupted texture DOES produce a different post-quantization artifactId at every N from 0 through 7, proving the texture-upload/sampling path itself functions correctly and is not degenerate -- the zero cross-hardware divergence is fully and only explained by UploadTexture() always using VK_FILTER_NEAREST (already diagnosed in 17-04-SUMMARY.md and 17-CAPTURE-RESULTS-ROUND1.md's own caveat), not by a masked/invisible corruption path."
  - "[Rule 3 - Blocking] texturing-fixture-definition.json/texturing_vertex_shader.glsl/texturing_fragment_shader.glsl/texturing-vertex-data.raw (authored in 17-03/17-04) were never added to processing_dispatch/CMakeLists.txt's POST_BUILD copy list -- only texturing-source-image.raw had been added (by 17-04 itself, since it's also consumed by capture_harness). This plan's counter-test is the first GTest consumer of the shader/fixture-JSON/vertex-data files specifically, so the same gap 17-06 found and fixed for lighting/blending recurred here for texturing's remaining files. Added all four missing files to the copy list."

requirements-completed: [RENDTOL-02]

coverage:
  - id: D1
    description: "Texturing's byteQuantMode is derived independently via binary-search-against-a-counter-test (D-06), starting from 17-CAPTURE-RESULTS-ROUND1.md's real maxAbsDelta=0.0, never guessed a priori -- and the zero-divergence result is confirmed honest (not masking a hidden bug) by proving the counter-test's own corruption still diverges at every N from 0 through 7"
    requirement: "RENDTOL-02"
    verification:
      - kind: automated_test
        ref: "processing_conformance_security_test (ctest #119, includes Secv01RenderTexturingCounterTest.TexturingWrongSourceImageStillDiverges -- ctest's per-target granularity does not expose individual TEST_F names, mirroring 17-06's own noted limitation) -- 7/7 passed at N=7; N=8 confirmed to deterministically fail (re-run twice) before selecting N=7"
        status: pass
    human_judgment: false
  - id: D2
    description: "Texturing gets its own dedicated counter-test file (D-07), mirroring secv01_tex3d_counter_test.cpp's per-fixture-file precedent and 17-06's two prior counter-tests, whose 'wrong' variant substitutes a fully bit-inverted corrupted source texture image -- the closest structural analog to secv01_tex3d_counter_test.cpp's byte-perturbed-model precedent applied to a sampled image"
    requirement: "RENDTOL-02"
    verification:
      - kind: other
        ref: "New file secv01_render_texturing_counter_test.cpp, registered as the sixth source in processing_conformance_security_test's CMake target alongside the five pre-existing sources"
        status: pass
    human_judgment: false
  - id: D3
    description: "Production fixture JSON and counter-test inline JSON agree exactly on the final chosen byteQuantMode value, with a citation-trail description in the production JSON covering the real measured zero divergence"
    requirement: "RENDTOL-02"
    verification:
      - kind: other
        ref: "texturing-fixture-definition.json parameters[0].default=7 matches both of secv01_render_texturing_counter_test.cpp's inline JSON literals; description cites the real measured maxAbsDelta=0.0 (with the VK_FILTER_NEAREST explanation) and the counter-test-derived N=7/N=8-boundary finding"
        status: pass
    human_judgment: false
  - id: D4
    description: "Full regression gate confirms no prior fixture/counter-test regressed from this plan's changes"
    requirement: "RENDTOL-02"
    verification:
      - kind: integration
        ref: "ctest -R \"processing|Processing|capture|Capture|render|Render\" -- 19/19 passed (1 pre-existing unrelated CancellationTest.CancelMidRenderPass skip, unchanged from prior plans)"
        status: pass
    human_judgment: false

duration: 40min
completed: 2026-08-19
status: complete
---

# Phase 17 Plan 07: Texturing byteQuantMode Derivation Summary

**Texturing's byteQuantMode=7, empirically derived via binary search against a new dedicated SECV-01-style counter-test whose corruption is a fully bit-inverted source texture image -- completing RENDTOL-02's tolerance derivation for all three render fixtures (lighting=5, blending=6, texturing=7), and confirming texturing's Round 1 "zero divergence" finding is honest (not a hidden bug like lighting's) because the counter-test's own corruption still diverges at every safe N.**

## Performance

- **Duration:** ~40 min
- **Completed:** 2026-08-19
- **Tasks:** 2
- **Files modified:** 5 (1 new counter-test file, 1 new corrupted texture fixture, 2 CMakeLists.txt, 1 production fixture JSON)

## Accomplishments

- Created `secv01-wrong-texture-source-image.raw`: a 16384-byte, byte-for-byte bit-inversion of `texturing-source-image.raw` (`wrongByte = 255 - correctByte` for every byte) -- verified exact length and full inversion (every byte differs) before committing. Unlike a structured `.mnn` model format, a raw RGBA8 buffer has no parseable structure to break, so a full inversion is the simplest, maximal-divergence "wrong" variant, with no fallback-offset search needed.
- Wrote `secv01_render_texturing_counter_test.cpp` (`Secv01RenderTexturingCounterTest.TexturingWrongSourceImageStillDiverges`), mirroring `secv01_tex3d_counter_test.cpp`'s byte-perturbed-input-corruption precedent and 17-06's two prior render counter-tests' structure (`HasUsableVulkanDevice()` skip guard, `Create()`+`Process()`+binary `memcmp` on `artifacts[0].artifactId`).
- Ran a real, rebuild-and-run binary search (not a table lookup) over `byteQuantMode` N in `[0,8]` against the corrupted-texture counter-test, starting from the real captured `maxAbsDelta=0.0` floor (N=0): N=0 through N=7 all pass, N=8 fails (masks every byte to 0x00 -- the exact degenerate all-zero edge case RESEARCH.md's own Tolerance Derivation Methodology anticipated for N=8, not a surprise). Re-confirmed both N=7 (pass) and N=8 (fail) deterministic via two independent re-runs each. Final value: **N=7**.
- Confirmed texturing's Round 1 zero-divergence finding is honest, not a hidden defect the way lighting's turned out to be in 17-06: this counter-test's own fully bit-inverted corruption produces a different post-quantization `artifactId` at every N from 0 through 7, proving the texture-upload/sampling path is functioning correctly. The zero cross-hardware divergence remains fully explained by `UploadTexture()` always using `VK_FILTER_NEAREST` (already diagnosed in 17-04-SUMMARY.md and 17-CAPTURE-RESULTS-ROUND1.md's own caveat), not by any masked/invisible corruption path.
- Registered the new source as the sixth `processing_conformance_security_test` source in `CMakeLists.txt`.
- Found and fixed a Rule 3 blocking gap (same class as 17-06's own finding for lighting/blending): `texturing-fixture-definition.json`, `texturing_vertex_shader.glsl`, `texturing_fragment_shader.glsl`, and `texturing-vertex-data.raw` had never been added to `processing_dispatch/CMakeLists.txt`'s POST_BUILD copy list (only `texturing-source-image.raw` had been added, by 17-04, since it is also consumed directly by `capture_harness`). This plan's counter-test is the first GTest consumer of these remaining files, so the gap was invisible until now. Added all four missing files to the copy list.
- Wired the final value into `texturing-fixture-definition.json`'s new `parameters` array, with a citation-trail description covering both the real measured zero divergence and the counter-test-derived N=7/N=8-boundary finding.
- Verified the full `processing_conformance_security_test` suite (7/7) and the broader `processing|render|capture|dispatch`-scoped ctest run (19/19, 1 pre-existing unrelated `CancellationTest.CancelMidRenderPass` skip) still pass after all changes.

## Task Commits

Each task was committed atomically (submodule-first, then outer-repo pointer bump, per this project's convention):

1. **Task 1: Create the corrupted texture asset and prove it diverges before committing** - `9ea5f132` (SuperGenius submodule, feat)
2. **Task 2: Derive texturing's byteQuantMode and write its counter-test** - `9df15d31` (SuperGenius submodule, feat)
3. Outer-repo submodule pointer bump - `8a2dbee` (chore)

**Plan metadata:** (this commit) `docs(17-07): complete plan`

## Files Created/Modified

- `SuperGenius/test/src/processing_conformance_security/fixtures/secv01-wrong-texture-source-image.raw` - new 16384-byte, fully bit-inverted corrupted copy of `texturing-source-image.raw`
- `SuperGenius/test/src/processing_conformance_security/secv01_render_texturing_counter_test.cpp` - new SECV-01-style counter-test, `TexturingWrongSourceImageStillDiverges`
- `SuperGenius/test/src/processing_conformance_security/CMakeLists.txt` - registered the new source as the sixth `processing_conformance_security_test` source
- `SuperGenius/test/src/processing_dispatch/CMakeLists.txt` - added 4 missing texturing fixture files (JSON definition, both shaders, vertex data) to the POST_BUILD copy list
- `SuperGenius/test/src/processing_dispatch/texturing-fixture-definition.json` - added `parameters: [{byteQuantMode: 7}]` with a citation-trail description covering the real zero-divergence measurement and the counter-test-derived N=7/N=8-boundary finding

## Decisions Made

- Texturing's byteQuantMode=7 (binary search boundary at N=8, the theoretical all-zero-byte edge case), derived purely from the counter-test's own corruption-detection boundary since the real captured divergence is genuinely zero (not stale/degenerate).
- Confirmed (not merely assumed) that texturing's zero-divergence Round 1 result is a real, honest finding rather than a hidden bug: the counter-test's own corruption diverges at every safe N, unlike lighting's 17-06 finding where the corruption was invisible at ANY N until a real shader bug was fixed.
- Fixed the `processing_dispatch/CMakeLists.txt` fixture-copy gap for texturing's remaining files in the same task that needed them (mirroring 17-06's identical fix for lighting/blending), rather than deferring it as a separate follow-up.
- Did not re-run `requirements.mark-complete` for RENDTOL-02 -- per the plan's explicit instruction, this phase is 7/8 plans in and Round 2 verification (17-08) is still pending for all three fixtures; REQUIREMENTS.md's premature-completion discrepancy (flagged since 17-02, re-flagged in 17-05/17-06) remains open for revisit at phase close.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Added 4 missing texturing fixture files to processing_dispatch/CMakeLists.txt's copy list**
- **Found during:** Task 2, first build+run attempt of the new counter-test
- **Issue:** All test binaries in this project share one `RUNTIME_OUTPUT_DIRECTORY` (`test_bin/`, per `cmake/functions.cmake`'s `addtest()`), and cross-test-binary fixture sharing depends on each fixture's owning `CMakeLists.txt` copying its files into that shared directory (`processing_dispatch/` subfolder). Only `texturing-source-image.raw` had ever been added to this copy list (by 17-04, since `capture_harness` also consumes it directly) -- `texturing-fixture-definition.json`, `texturing_vertex_shader.glsl`, `texturing_fragment_shader.glsl`, and `texturing-vertex-data.raw` (also authored in 17-03/17-04) had never been added, because no GTest binary had ever needed to resolve their `file://processing_dispatch/...` URIs until this plan's counter-test.
- **Fix:** Added `texturing-fixture-definition.json`, `texturing_vertex_shader.glsl`, `texturing_fragment_shader.glsl`, and `texturing-vertex-data.raw` to `processing_dispatch/CMakeLists.txt`'s POST_BUILD copy command.
- **Files modified:** `SuperGenius/test/src/processing_dispatch/CMakeLists.txt`
- **Verification:** After rebuilding `processing_dispatch_test` (whose POST_BUILD step performs the actual copy), the new counter-test's `file://processing_dispatch/texturing_vertex_shader.glsl` / `texturing_fragment_shader.glsl` / `texturing-vertex-data.raw` URIs resolve correctly and the test builds and passes.
- **Committed in:** `9df15d31`

---

**Total deviations:** 1 auto-fixed (1 blocking gap)
**Impact on plan:** No scope creep -- the fix was strictly necessary to make this plan's own counter-test buildable and runnable, and mirrors 17-06's own identical fix for the other two fixtures' equivalent gap.

## Issues Encountered

None beyond the Rule 3 deviation documented above. Unlike 17-06's lighting fixture, texturing's counter-test passed on the very first build once the missing fixture files were copied -- no hidden shader/uniform-packing bug was found, and the real zero-divergence Round 1 result was confirmed honest rather than degenerate.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- RENDTOL-02's byteQuantMode derivation is now complete for all three fixtures: lighting=5, blending=6, texturing=7, each independently derived (D-07 -- no shared/global tolerance) and each proven via its own dedicated counter-test not to mask a deliberate corruption.
- Round 2 verification (17-08) remains pending for all three fixtures. For texturing specifically, Round 2 should capture fresh real cross-hardware divergence data with `byteQuantMode=7` now declared (previously it fell back to N=0/identity) -- this plan did not re-run a cross-machine capture, only the local counter-test binary search.
- For lighting, Round 2 must additionally re-capture against the corrected shader from 17-06 (that fixture's Round 1 "zero divergence" figure is known-stale, unlike texturing's, which this plan confirmed is genuinely zero and not degenerate).
- REQUIREMENTS.md's RENDTOL-01/02 premature-completion discrepancy (flagged since 17-02, re-flagged in 17-05/17-06) remains open for revisit at phase close -- this plan did not re-run `requirements.mark-complete`, consistent with 17-05/17-06's own decision.

---
*Phase: 17-render-path-cross-hardware-tolerance*
*Completed: 2026-08-19*

## Self-Check: PASSED

- FOUND: SuperGenius/test/src/processing_conformance_security/secv01_render_texturing_counter_test.cpp
- FOUND: SuperGenius/test/src/processing_conformance_security/fixtures/secv01-wrong-texture-source-image.raw
- FOUND: .planning/workstreams/sgproc-render/phases/17-render-path-cross-hardware-tolerance/17-07-SUMMARY.md
- FOUND commit 9ea5f132 (Task 1)
- FOUND commit 9df15d31 (Task 2)
- FOUND commit 8a2dbee (submodule pointer bump)
