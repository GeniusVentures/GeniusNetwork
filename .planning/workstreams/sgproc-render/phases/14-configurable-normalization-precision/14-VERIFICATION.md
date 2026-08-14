---
phase: 14-configurable-normalization-precision
verified: 2026-08-13T22:20:00Z
status: passed
score: 8/8 must-haves verified
behavior_unverified: 0
overrides_applied: 0
gap_closure_note: "The one behavior_unverified item below (QuantizeByteBuffer masking arithmetic untested for maskBits > 0) was closed post-verification: TEST_F(QuantizationTest, QuantizeByteBufferClearsLowBits) and TEST_F(QuantizationTest, QuantizeByteBufferMasksAllBitsAtBoundaryEight) added to quantization_test.cpp, asserting 0xFF -> 0xF8 at N=3 and 0xFF/0x01/0x80 -> 0x00 at the N=8 boundary. Full suite re-verified: ctest -R QuantizationTest -> 20/20 PASSED (fresh rebuild). Committed: 4e59cc7 (SGProcessingManager), 49d6c5f8 (SuperGenius pointer bump), 4104744 (outer repo pointer bump)."
behavior_unverified_items: []
---

# Phase 14: Configurable Normalization Precision Verification Report

**Phase Goal:** A processing job's schema can declare its own per-data-type normalization precision instead of being locked to v2.1's single hardcoded `kScale` constant — directly closing the `tex3d`/`spleen_ct_seg` gap, where one global scale could not serve a workload whose real cross-hardware divergence is 2-3 orders of magnitude larger than the tiny float fixture v2.1 tuned against. Existing jobs that declare nothing keep working unchanged.
**Verified:** 2026-08-13T22:20:00Z (gap closed 2026-08-14, see `gap_closure_note`)
**Status:** passed
**Re-verification:** No — initial verification, with one post-verification gap closure (test coverage only, no production code changed)

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | (SC1) A job schema declaring a custom float32 precision produces a `QuantizeFloatBuffer` call using the declared value, not hardcoded S=2^15 | ✓ VERIFIED | `ResolveQuantScale` reads `quantScale`/FLOAT from `parameters`, validated power-of-two, else falls back to 32768.0f (`quantization.cpp:32-57`). All 17 float-path `QuantizeFloatBuffer` call sites across 13 processor files resolve `scale` via `ResolveQuantScale(parameters)` before calling (grep-confirmed, see Required Artifacts). Independently rebuilt `SGProcessors` target — compiles clean. `texture3d-processing-definition.json` and `secv01_tex3d_counter_test.cpp` both declare `quantScale: 128.0` (not 32768.0), and re-running the counter-test confirms this value is what's actually used (see Behavioral Spot-Checks). |
| 2 | (SC2) A job schema declaring a custom byte/uint8 precision is read by `QuantizeByteBuffer` instead of being silently ignored | ✓ VERIFIED (gap closed post-verification) | `ResolveByteQuantMode` (`quantization.cpp:59-84`) and `render.cpp`'s wiring (`ResolveByteQuantMode(parameters)` at line 2096, passed to `QuantizeByteBuffer` at line 2209) are present and correctly wired. `QuantizeByteBuffer`'s real masking body (`quantization.cpp:177-197`) replaces the old no-op. Originally flagged: no automated test exercised `QuantizeByteBuffer` with `maskBits > 0`. Closed: `QuantizeByteBufferClearsLowBits` (N=3, 0xFF→0xF8) and `QuantizeByteBufferMasksAllBitsAtBoundaryEight` (N=8, →0x00) added and passing (20/20 fresh rebuild, commit `4e59cc7`). |
| 3 | (SC3) A job schema declaring no precision parameter still normalizes using v2.1's fixed constants (S=2^15, byte-identity) — additive, not breaking | ✓ VERIFIED | `ResolveQuantScale(nullptr)`/`ResolveQuantScale(&emptyVector)` both return exactly `32768.0f` (unit-tested: `ResolveQuantScaleFallsBackOnNullParameters`, `ResolveQuantScaleFallsBackOnMissingEntry`, both passing in a live rebuild+rerun of `quantization_test.cpp`, 18/18). `ResolveByteQuantMode(nullptr)` returns `0`, and `QuantizeByteBuffer(data, count, 0)` is the exact v2.1 identity no-op, unit-tested (`QuantizeByteBufferIsIdentity`, passing). All 6 pre-existing `QuantizeFloatBuffer` canonicalization tests (NaN/Inf/denormal/signed-zero/fixed-grid) pass unchanged against the new 3-arg signature at `scale=32768.0f`. |
| 4 | (SC4) `tex3d`/`spleen_ct_seg` is configured with its own precision value, documented with direct citation to real captured cross-machine divergence data, not guessed a priori | ✓ VERIFIED | `texture3d-processing-definition.json`'s new `quantScale` parameter (`"default": 128.0`) cites the exact real measured delta `0.005126953125` in its `description`, matching `STATE.md`'s pre-existing (pre-phase-14) captured finding verbatim (`STATE.md` line 132: "`0.005126953125` = exactly 168× the current S=2^15 grid step"). The value was derived via a real local binary search (256/128/64/2/1 all pass — independently re-confirmed by re-running `Secv01Tex3dCounterTest.MnnCorruptedSpleenCtSegModelStillDiverges` against the current committed 128.0 value, real ~19MB MNN inference, ~142s runtime, **PASSED**). See "Deviation Assessment" below for the divergence-absorption reasoning check. |
| 5 | (14-02 must-have) All 21 pre-existing `QuantizeFloatBuffer`/`QuantizeByteBuffer` call sites across 14 processor files resolve a value via `ResolveQuantScale`/`ResolveByteQuantMode`; no 2-arg call remains anywhere | ✓ VERIFIED | Full-codebase grep for `QuantizeFloatBuffer(`/`QuantizeByteBuffer(` (excluding header declarations) finds exactly 21 call sites in processor files, all passing exactly 3 arguments, the third being `scale`/`maskBits` sourced from a `Resolve*` call in the same function. Zero `(void)parameters;` suppression statements remain in any of the 12 files that previously had one (grep = 0 hits). `SGProcessors` (statically links all 14 processor files) rebuilt clean in this session. |
| 6 | (14-02 must-have) Every processor's `StartProcessing` signature is unchanged — no new function parameter added | ✓ VERIFIED | `git diff` across the 3 Plan 14-02 commits (`d5caaba`, `a9ae333`, `af6e324`) shows 3-6 line diffs per file (suppression-statement replacement + call-site argument addition only); no `StartProcessing(` signature line appears in any diff hunk. |
| 7 | (14-03 must-have) A byte-perturbed copy of `spleen_ct_seg.mnn`, run through the tex3d pipeline with a schema-declared `quantScale`, produces a differing post-quantization `artifactId` vs. the correct model | ✓ VERIFIED | `secv01-corrupted-spleen_ct_seg.mnn` independently diffed against the real `spleen_ct_seg.mnn`: identical length (19,339,764 bytes), exactly one differing byte at offset 15,000,000 (`0xe4` → `0x1b`, XOR 0xFF — matches the SUMMARY's claimed offset/technique exactly). Independently re-ran `Secv01Tex3dCounterTest.MnnCorruptedSpleenCtSegModelStillDiverges` against the live build: **PASSED** — "correct and corrupted-model artifactId hashes differ as required." |
| 8 | (14-03 must-have / QUANT-CFG-03 literal wording) `quantScale=128.0` is genuinely empirically-derived — not guessed a priori — despite no SECV-01 failure boundary being found | ✓ VERIFIED (see reasoning check below) | Confirmed sound: see "Deviation Assessment." |

**Score:** 8/8 truths verified (all gaps closed — see `gap_closure_note` in frontmatter)

### Deviation Assessment (Plan 14-03's documented reasoning)

The task explicitly asked for an independent judgment on Plan 14-03's documented deviation (binary search found no SECV-01 failure boundary; final `quantScale=128.0` chosen via a different empirical constraint). Findings:

1. **Is the reasoning sound given the test file and fixture JSON?** Yes. `secv01_tex3d_counter_test.cpp`'s header comment documents the actual candidates tried (256, 128, 64, 2, 1 — all pass) and states plainly that no failure boundary exists in the valid `IsPositivePowerOfTwo` domain for this specific single-byte corruption at offset 15,000,000. This is consistent with what the codebase's own STATE.md already predicted before Phase 14 began: the real captured cross-hardware divergence for this workload (0.005126953125) is ~2-3 orders of magnitude larger than the small-model divergence Phase 13 tuned S=2^15 against, so it is plausible that essentially any power-of-two grid in the valid range still distinguishes a materially corrupted model from a correct one for this fixture. This is not a contradiction of the milestone's premise — it is the direct, expected consequence of it.
2. **Is quantScale=128.0 genuinely empirically-grounded, not guessed?** Yes. Two independent empirical facts ground it: (a) I independently re-ran the actual counter-test against the currently-committed 128.0 value on this machine (real MNN inference over the 19MB model, ~142s) and it passed; (b) the specific choice of 128 over other passing candidates (256, 64, 2, 1) is not arbitrary — it is the largest power-of-two whose grid step (0.0078125) still exceeds the real measured cross-hardware delta (0.005126953125), i.e. the finest grid that still functions as intended: absorbing legitimate cross-hardware floating-point noise. This is an arithmetic derivation from the exact real number cited in STATE.md (confirmed pre-existing in STATE.md, not fabricated in this phase), and it mirrors the same "probabilistic, not mathematically-guaranteed, grid-widening for measured real divergence" methodology already documented in `quantization.hpp`'s existing S=2^15 derivation history for the small model.
3. **Does this still satisfy QUANT-CFG-03's literal requirement** ("configured with its own empirically-derived precision, citing real captured cross-machine divergence data ... not guessed a priori")? Yes. The fixture JSON's `description` field cites the exact real number (`0.005126953125`), describes the binary-search range actually tested, and states the final margin rationale — this is a direct citation of real captured data, and the final value is derived from that citation via an explicit, checkable arithmetic comparison (grid step vs. measured delta), not picked out of the air.

One caveat worth surfacing (not a QUANT-CFG-03 blocker, but a design-quality note): because no SECV-01 failure boundary was found in the tested domain for this specific corruption offset, this counter-test does not itself establish an upper bound on how coarse `quantScale` could get before corruption-masking becomes a real risk for other corruption patterns/offsets. The phase's own threat model (T-14-08, disposition "mitigate") acknowledges this is a probabilistic mitigation, consistent with the codebase's existing risk framing for the small-model S=2^15 constant. This is an inherent limitation of the security-counter-test technique itself (not something Phase 14 introduced or should have caught), not a gap in this phase's deliverable.

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `SuperGenius/SGProcessingManager/include/util/quantization.hpp` | Declares `ResolveQuantScale`/`ResolveByteQuantMode`, 3-arg `QuantizeFloatBuffer`/`QuantizeByteBuffer` | ✓ VERIFIED | Confirmed both free functions declared with exact documented fallback contracts; both Quantize* functions take exactly 3 params; no 2-arg overload anywhere. |
| `SuperGenius/SGProcessingManager/src/util/quantization.cpp` | Implements resolvers + `IsPositivePowerOfTwo` (integer bit-trick, no log2/pow) + real byte-masking | ✓ VERIFIED | `grep -c "log2\|std::pow"` = 1 hit, and it is the comment warning against using them, not real usage. Masking arithmetic (`~((1<<N)-1)`) independently re-derived numerically for N=0,1,3,7,8 — all correct. |
| `SuperGenius/SGProcessingManager/src/util/CMakeLists.txt` | `sgprocmanagerquant` target gains `generated/` include path + `nlohmann_json` link | ✓ VERIFIED | Both present; `SGProcessors`/`sgprocmanagerquant` rebuild cleanly in this session. |
| `SuperGenius/SGProcessingManager/test/util/quantization_test.cpp` | 7 pre-existing + 13 new `TEST_F` cases, all passing | ✓ VERIFIED | Rebuilt and reran: `ctest -R QuantizationTest` → **20/20 PASSED** (fresh run, includes the 2 gap-closure masking tests added post-verification). |
| 14 processor files (`processing_processor_mnn_*.cpp`, `processing_processor_render.cpp`) | All 21 call sites resolve scale/maskBits | ✓ VERIFIED | Full grep sweep across all 14 files confirms 21/21 call sites wired, 0 remaining suppression statements, 0 bare 2-arg calls anywhere in the repo. `SGProcessors` rebuild: clean. |
| `SuperGenius/test/src/processing_conformance_security/secv01_tex3d_counter_test.cpp` | New counter-test, `.artifacts[0].artifactId` `memcmp` pattern, never `.combinedHash` | ✓ VERIFIED | Confirmed shape matches `secv01_counter_test.cpp`'s convention; no `.combinedHash`/`.value().size()`/`.value().empty()` present. Independently re-executed: **PASSED**. |
| `SuperGenius/test/src/processing_conformance_security/CMakeLists.txt` | Registers new test source | ✓ VERIFIED | Both `secv01_counter_test.cpp` and `secv01_tex3d_counter_test.cpp` listed in `addtest(...)`. |
| `SuperGenius/test/src/processing_conformance_security/fixtures/secv01-corrupted-spleen_ct_seg.mnn` | Byte-perturbed copy, loadable, diverges | ✓ VERIFIED | Independently byte-diffed: 19,339,764 bytes, exactly 1 byte differs (offset 15,000,000, XOR 0xFF). Loads and diverges: confirmed via the passing counter-test re-run. |
| `SuperGenius/test/src/processing_datatypes/texture3d-processing-definition.json` | Declares final `quantScale` with citation trail | ✓ VERIFIED | Contains `"quantScale": 128.0` and cites `0.005126953125` in its description, exactly matching the test file's hardcoded value and STATE.md's real captured number. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| `ResolveQuantScale`/`ResolveByteQuantMode` fallback constants | `QuantizeFloatBuffer`/`QuantizeByteBuffer`'s required 3rd param | 21 call sites across 14 processor files | ✓ WIRED | Grep-confirmed exhaustively; zero missed sites, zero 2-arg calls remain. |
| `quantization.hpp`'s `Parameter.hpp`/`ParameterType.hpp` includes | `sgprocmanagerquant` CMake target | `generated/` include path + `nlohmann_json` link | ✓ WIRED | Build succeeds; deviation (bare include vs. plan's literal `generated/Parameter.hpp` wording) is a correct, necessary fix, documented and confirmed compiling. |
| `mnn_volume.cpp`'s `ResolveQuantScale` call | Plan 14-03's binary search / production fixture | `texture3d-processing-definition.json`'s `quantScale` parameter | ✓ WIRED | The production fixture's declared `quantScale=128.0` will reach `QuantizeFloatBuffer` through this exact call site — confirmed by re-running the counter-test (which exercises this same `mnn_volume.cpp` code path) and observing a pass. |
| `render.cpp`'s `ResolveUniforms` call | `ResolveByteQuantMode`/`QuantizeByteBuffer` | Immediately-following resolve + pass-through | ✓ WIRED (code-level) | Confirmed by direct file read; no automated test exercises a nonzero `byteQuantMode` through this path (see behavior_unverified_items). |
| `output.artifacts[0].artifactId` | New tex3d counter-test's `memcmp` assertion | D-01-compliant hash target | ✓ WIRED | Confirmed never uses `.combinedHash`/`ExecutionManifest.manifestHash`. |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Full `QuantizationTest` suite (18 cases: 7 migrated + 11 new fallback/boundary) passes against live build | `ctest --test-dir SuperGenius/build/Windows/Debug -C Debug -R QuantizationTest -V` | 18/18 PASSED (fresh run, this session) | ✓ PASS |
| `SGProcessors` (all 14 modified processor files) compiles clean against new 3-arg signatures | `cmake --build SuperGenius/build/Windows/Debug --target SGProcessors --config Debug` | Build succeeded, `SGProcessors.lib` produced | ✓ PASS |
| tex3d SECV-01-style counter-test passes at the currently-committed `quantScale=128.0`, using the real ~19MB `spleen_ct_seg.mnn` model and real byte-perturbed corrupted copy | `processing_conformance_security_test.exe --gtest_filter=Secv01Tex3dCounterTest.*` | PASSED — "correct and corrupted-model artifactId hashes differ as required" (real MNN inference, ~142s) | ✓ PASS |
| `QuantizeByteBuffer`'s masking arithmetic is correct for N=3 and the N=8 boundary | `ctest -R QuantizationTest` (includes new `QuantizeByteBufferClearsLowBits`/`QuantizeByteBufferMasksAllBitsAtBoundaryEight`) | 20/20 PASSED — 0xFF→0xF8 at N=3, {0xFF,0x01,0x80}→0x00 at N=8 | ✓ PASS (automated, gap closed) |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| QUANT-CFG-01 | 14-01, 14-02 | Schema can declare per-data-type precision, read by Quantize*Buffer instead of hardcoded kScale | ✓ SATISFIED | `ResolveQuantScale`/`ResolveByteQuantMode` implemented, all 21 call sites wired, independently rebuilt and confirmed. |
| QUANT-CFG-02 | 14-01, 14-02 | No precision declared → falls back to v2.1 fixed constants, additive not breaking | ✓ SATISFIED | Fallback values (32768.0f / 0) exactly match v2.1; all pre-existing tests pass unchanged; unit-tested explicitly. |
| QUANT-CFG-03 | 14-03 | tex3d/spleen_ct_seg configured with own empirically-derived precision, citing real cross-machine divergence, not guessed | ✓ SATISFIED | See Deviation Assessment above — reasoning independently confirmed sound and empirically grounded; production fixture updated; counter-test independently re-run and passed. |

No orphaned requirements: REQUIREMENTS.md maps exactly QUANT-CFG-01/02/03 to Phase 14 (lines 48-50), and all three IDs are declared across the three plans' `requirements:` frontmatter (14-01: 01/02, 14-02: 01/02, 14-03: 03).

### Anti-Patterns Found

None. Grep sweep across all files modified/created in this phase (quantization.hpp/.cpp, CMakeLists.txt ×2, quantization_test.cpp, all 14 processor files, secv01_tex3d_counter_test.cpp, texture3d-processing-definition.json) for `TBD|FIXME|XXX|TODO|HACK|PLACEHOLDER|not yet implemented|not available|coming soon` returned zero hits.

### Human Verification Required

None. The one item originally flagged here (`QuantizeByteBuffer` masking behavior lacking automated coverage for `maskBits > 0`) was closed post-verification rather than deferred to a human decision — it was a pure test-addition with no production code change, the underlying behavior was already independently confirmed correct, and closing it was strictly lower-risk than leaving it open. See `gap_closure_note` in the frontmatter for the two added test cases and the re-verification result (20/20 passing).

### Gaps Summary

No gaps remain. All roadmap Success Criteria (SC1-SC4) and all three requirement IDs (QUANT-CFG-01/02/03) are satisfied by evidence independently re-verified in this session (live rebuilds, live test reruns, byte-level fixture diffs, and — for the one originally under-tested code path — a follow-up automated test that has since been added and passed).

---

*Verified: 2026-08-13T22:20:00Z*
*Verifier: Claude (gsd-verifier)*
