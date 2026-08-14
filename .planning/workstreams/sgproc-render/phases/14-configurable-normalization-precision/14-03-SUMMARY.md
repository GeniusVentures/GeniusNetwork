---
phase: 14-configurable-normalization-precision
plan: 03
subsystem: processing
tags: [secv-01, counter-test, ctest, mnn, quantization, tex3d, cross-hardware-tolerance]

# Dependency graph
requires:
  - phase: 14-configurable-normalization-precision
    plan: 02
    provides: "mnn_volume.cpp's ResolveQuantScale-wired StartProcessing call site -- the real quantScale schema parameter this plan's binary search actually measures against"
provides:
  - "New CTest case Secv01Tex3dCounterTest.MnnCorruptedSpleenCtSegModelStillDiverges proving tex3d/spleen_ct_seg's own coarser quantScale still catches a genuinely corrupted model"
  - "Empirically-derived quantScale=128.0 (2^7) for tex3d/spleen_ct_seg, wired into texture3d-processing-definition.json's schema parameters"
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Binary std::memcmp != 0 on output.artifacts[0].artifactId only (D-13, mirroring secv01_counter_test.cpp) -- never combinedHash"
    - "quantScale citation-trail discipline: fixture JSON's parameter description cites the exact measured cross-hardware delta and the binary-search range searched, mirroring 13-04-PLAN.md's S=2^15 citation for the small model"

key-files:
  created:
    - SuperGenius/test/src/processing_conformance_security/secv01_tex3d_counter_test.cpp
    - SuperGenius/test/src/processing_conformance_security/fixtures/secv01-corrupted-spleen_ct_seg.mnn
  modified:
    - SuperGenius/test/src/processing_conformance_security/CMakeLists.txt
    - SuperGenius/test/src/processing_datatypes/texture3d-processing-definition.json

key-decisions:
  - "No SECV-01 failure boundary exists in the valid quantScale domain for this corruption/offset -- a local binary search (256, 128, 64, 2, 1) found the counter-test passes at every tested power-of-two down to the floor (S=1). This differs from Phase 13's small-model search, which found a genuine S=2^14 failure boundary."
  - "Because no failure boundary exists to margin above, the final quantScale=128.0 (2^7) was chosen by the other empirical constraint D-10 cites: the finest (largest) power-of-two grid step that still exceeds the real measured cross-hardware divergence delta (0.005126953125), giving ~1.53x margin at S=128 vs a sub-unity (non-absorbing) margin at S=256."

patterns-established:
  - "When a security counter-test binary search finds no failure boundary within the valid parameter domain, fall back to the divergence-absorption constraint (grid step >= measured real delta) to choose the final value, rather than guessing or picking an arbitrary point -- both constraints are cited explicitly in the fixture JSON's description field for future auditability."

requirements-completed: [QUANT-CFG-03]

coverage:
  - id: T-14-07
    description: "A byte-perturbed copy of spleen_ct_seg.mnn, run through the same MNN volume pipeline shape as texture3d-processing-definition.json with a schema-declared quantScale, produces a post-quantization artifactId that differs from the correct model's artifactId"
    requirement: "QUANT-CFG-03"
    verification:
      - kind: integration
        ref: "SuperGenius/test/src/processing_conformance_security/secv01_tex3d_counter_test.cpp#Secv01Tex3dCounterTest.MnnCorruptedSpleenCtSegModelStillDiverges"
        status: pass
    human_judgment: false
  - id: T-14-08
    description: "tex3d/spleen_ct_seg's final quantScale value is chosen via the same binary-search-against-a-counter-test methodology Phase 13 used for the small MNN model, not guessed a priori"
    requirement: "QUANT-CFG-03"
    verification:
      - kind: other
        ref: "Local binary search over power-of-two quantScale candidates (256, 128, 64, 2, 1) against Secv01Tex3dCounterTest, run via repeated cmake --build + direct --gtest_filter invocation on this machine; all passed, no failure boundary found; final value chosen by the divergence-absorption constraint instead (documented in secv01_tex3d_counter_test.cpp's header comment and this plan's key-decisions)"
        status: pass
    human_judgment: false
  - id: quantscale-citation
    description: "texture3d-processing-definition.json's new quantScale parameter cites the real measured delta (0.005126953125) and matches the test's hardcoded value (128.0) exactly"
    requirement: "QUANT-CFG-03"
    verification:
      - kind: other
        ref: "grep '0.005126953125' texture3d-processing-definition.json and grep '\"default\": 128.0' in both files -- both confirmed present"
        status: pass
    human_judgment: false

duration: 35min
completed: 2026-08-14
status: complete
---

# Phase 14 Plan 3: Tex3d Empirical Precision & SECV-01 Counter-Test Summary

**A byte-perturbed copy of the real ~19.3MB spleen_ct_seg.mnn model, run through a new SECV-01-style counter-test at tex3d's own empirically-derived quantScale=128.0 (2^7), proves the much coarser per-workload precision QUANT-CFG-03 exists to enable still catches a genuinely corrupted model -- closing the milestone's tex3d/spleen_ct_seg gap with cited real cross-hardware divergence data, not a guessed value.**

## Performance

- **Duration:** ~35 min
- **Completed:** 2026-08-14
- **Tasks:** 2
- **Files modified:** 4 (2 created, 2 modified) + 1 submodule pointer bump

## Accomplishments

- **Task 1** created `secv01-corrupted-spleen_ct_seg.mnn`: a byte-perturbed copy of the real 19339764-byte `spleen_ct_seg.mnn`, single byte at offset 15000000 (back-region weight-tensor area) XORed with `0xFF`. The first-tried offset worked on the first attempt (no fallback offsets needed) -- empirically confirmed via the real MNN::Interpreter load path in Task 2's counter-test to load successfully and produce a materially different post-quantization output than the original.
- **Task 2** created `secv01_tex3d_counter_test.cpp` (`Secv01Tex3dCounterTest.MnnCorruptedSpleenCtSegModelStillDiverges`), mirroring `secv01_counter_test.cpp`'s exact `Process()` -> `.artifacts[0].artifactId` -> `std::memcmp` methodology, registered as a second source in the existing `processing_conformance_security_test` CTest target (reusing its existing `fixtures/` `POST_BUILD` copy step).
- Ran a local binary search over power-of-two `quantScale` candidates directly against this new counter-test (rebuild + `--gtest_filter` invocation per candidate, ~2.5 min per run given the real ~19MB model's inference cost): **256, 128, 64, 2, 1 all pass** -- no SECV-01 failure boundary exists anywhere in the valid domain for this specific corruption/offset. This is a genuine, empirically-confirmed finding, not an assumption: the offset-15000000 byte flip propagates through this real segmentation network into a divergence large enough that even the coarsest possible integer grid (S=1) still distinguishes the corrupted artifactId from the correct one.
- Chose the final `quantScale=128.0` (2^7) using D-10's other cited empirical constraint (divergence absorption, not a SECV-01 margin): S=128's grid step (0.0078125) is the largest power-of-two grid step that still exceeds the real captured cross-hardware divergence delta (`0.005126953125`), giving ~1.53x margin; S=256's grid step (0.00390625) is smaller than that delta and would not reliably absorb it.
- Updated `texture3d-processing-definition.json`'s `parameters` array with a matching `quantScale: 128.0` entry, its `description` field citing the measured delta, the binary-search range searched, and the final chosen value -- mirroring 13-04-PLAN.md's citation-trail discipline.
- Re-ran the full `processing_conformance_security_test` suite (all 3 cases: 2 existing SECV-01 cases + the new tex3d case) and `processing_datatypes_test`'s two `Texture3D*` cases at the final value -- all pass, confirming no regression from the JSON fixture change.

## Task Commits

Committed inside the `SuperGenius` submodule (no `SGProcessingManager`-level changes needed this plan), then the outer `GeniusNetwork` pointer bumped:

1. **Task 1: Create the corrupted spleen_ct_seg.mnn fixture** -- `c0229f6a` (test, in SuperGenius)
2. **Task 2: Write the tex3d SECV-01 counter-test, binary-search the final quantScale, and commit the fixture JSON update** -- `ea8ca33b` (test, in SuperGenius)

**Submodule pointer bump:**
- Outer repo (`GeniusNetwork`): `a672966` (chore: bump SuperGenius pointer)

## Files Created/Modified

- `SuperGenius/test/src/processing_conformance_security/fixtures/secv01-corrupted-spleen_ct_seg.mnn` - New: byte-perturbed copy of `spleen_ct_seg.mnn` (single byte flipped at offset 15000000)
- `SuperGenius/test/src/processing_conformance_security/secv01_tex3d_counter_test.cpp` - New: `Secv01Tex3dCounterTest` fixture, one `TEST_F` case, header comment documenting the actual binary-search findings and the quantScale=128.0 rationale
- `SuperGenius/test/src/processing_conformance_security/CMakeLists.txt` - Added `secv01_tex3d_counter_test.cpp` as a second source in the existing `addtest(processing_conformance_security_test ...)` call
- `SuperGenius/test/src/processing_datatypes/texture3d-processing-definition.json` - Added `quantScale` parameter entry (`"default": 128.0`) with a citation-trail `description`

## Decisions Made

- **No SECV-01 failure boundary found in the valid quantScale domain for this corruption.** Unlike Phase 13's small-model search (which found a genuine S=2^14 failure boundary, prompting the S=2^15 choice), this plan's binary search tested 256, 128, 64, 2, and 1 (the floor of `IsPositivePowerOfTwo`'s valid domain) and found the counter-test passes at every single one. The single-byte weight-tensor flip at offset 15000000 in this real ~19MB segmentation model apparently propagates into a divergence far larger than any power-of-two grid in the valid range could mask.
- **Final value chosen by the divergence-absorption constraint instead of a SECV-01 margin.** Since there was no failure boundary to margin above, the final `quantScale=128.0` was chosen using D-10's other explicitly-cited empirical constraint: the grid must be coarse enough to actually absorb the real measured cross-hardware divergence (delta `0.005126953125`). S=128 is the finest (largest) power-of-two whose grid step (0.0078125) still exceeds that delta; S=256's grid step (0.00390625) does not. This keeps the chosen value maximally precise while still functionally serving the quantization tolerance's actual purpose, and it remains empirically confirmed to pass the security counter-test.
- Task 1's fixture offset (15000000, first tried, no fallback needed) succeeded on the first attempt -- same outcome pattern as 12-02-PLAN.md's small-model fixture (offset 15360, first tried).

## Deviations from Plan

### Auto-fixed Issues

None -- no bugs, missing functionality, or blocking issues required fixing during this plan.

### Process Deviation (documented, not a Rule 1-3 auto-fix)

**1. Binary search found no SECV-01 failure boundary; final value chosen by a different (but plan-anticipated) empirical constraint**
- **Found during:** Task 2's binary search
- **What the plan expected:** The plan's action text described a Phase-13-style search bracketing "the widest S where the test passes and the narrowest S where it starts failing," then choosing one power-of-two step above the confirmed failure boundary.
- **What actually happened:** The search (256, 128, 64, 2, 1) never found a failure boundary -- SECV-01 passed at every tested value down to the domain floor (S=1).
- **Resolution:** Used the plan's own explicitly-stated D-10 divergence-absorption criterion (grid step must exceed the real measured 0.005126953125 delta) to choose S=128 -- the finest power-of-two satisfying that criterion, still empirically confirmed to pass the counter-test. This is not a guess: both the absence of a failure boundary and the absorption-margin calculation are empirically grounded and documented in the test file's header comment and this plan's fixture JSON citation.
- **Files affected:** `secv01_tex3d_counter_test.cpp` (header comment documents the actual search results), `texture3d-processing-definition.json` (citation trail)
- **Commits:** `ea8ca33b`

## Issues Encountered

- Each binary-search iteration (rebuild + `--gtest_filter` run) took ~2.4-2.6 minutes given the real ~19.3MB model's inference cost (both correct and corrupted runs execute full MNN inference on a 96x96x96 volume) -- expected per this plan's own repo_note, not a stall.
- `ctest -R Secv01Tex3dCounterTest` does not match any registered CTest name -- this suite registers one CTest entry (`processing_conformance_security_test`) covering the whole GTest binary, not per-`TEST_F` CTest entries. Used the built executable directly with `--gtest_filter=Secv01Tex3dCounterTest.*` for per-candidate iteration during the search, and `ctest -R processing_conformance_security_test` for the final full-suite confirmation.

## User Setup Required

None -- no external service configuration, no package-manager installs. All work is in-repo C++/JSON/binary-fixture changes against the existing `processing_conformance_security_test` CTest target.

## Next Phase Readiness

- QUANT-CFG-03 is now fully satisfied: tex3d/spleen_ct_seg has its own empirically-derived `quantScale=128.0`, proven by a dedicated counter-test to still catch a genuinely corrupted model, cited against the real captured cross-machine divergence data (STATE.md's `0.005126953125` finding).
- Phase 14 (Configurable Normalization Precision) is now complete: Plan 14-01 (resolver infrastructure), Plan 14-02 (21 call sites wired), Plan 14-03 (tex3d's own value + security proof) all done.
- No blockers identified for Phase 15 (Validation Comparison Mechanism).

---
*Phase: 14-configurable-normalization-precision*
*Completed: 2026-08-14*

## Self-Check: PASSED

- FOUND: SuperGenius/test/src/processing_conformance_security/secv01_tex3d_counter_test.cpp
- FOUND: SuperGenius/test/src/processing_conformance_security/fixtures/secv01-corrupted-spleen_ct_seg.mnn (19339764 bytes)
- FOUND: SuperGenius/test/src/processing_conformance_security/CMakeLists.txt (contains secv01_tex3d_counter_test.cpp)
- FOUND: SuperGenius/test/src/processing_datatypes/texture3d-processing-definition.json (contains quantScale 128.0 and 0.005126953125 citation)
- FOUND commit c0229f6a (SuperGenius, Task 1)
- FOUND commit ea8ca33b (SuperGenius, Task 2)
- FOUND commit a672966 (GeniusNetwork outer repo, pointer bump)
