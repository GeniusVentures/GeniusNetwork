---
phase: 02-schema-extension-shader-spir-v-validation-pipeline
verified: 2026-07-31T00:17:03Z
reverified: 2026-07-31T21:20:00Z
status: passed
score: 9/9 truths verified (post-UAT)
behavior_unverified: 0
overrides_applied: 0
reverification_note: >
  All 3 human_verification items below were resolved via a real MSVC/VS2022 build+run
  (see 02-UAT.md). Two real bugs were found and fixed in the process: a dangling
  reference in GetCidForProc() that silently skipped shader compilation during
  dispatch, and missing/incorrect CMake wiring (SuperGenius couldn't find
  shaderc/SPIRV-Tools; GCC-style .a extensions instead of MSVC .lib). shader_compiler_test
  (6/6) and processing_dispatch_test (8/8, including a new permanent hlsl
  exception-safety test) now pass for real. Truths 7, 8, 9 below are now VERIFIED.
human_verification:
  - test: "Perform a full from-scratch (or from-source, matching 02-03's own precedent) configure+build+link of ProcessingBase (including the new SGShaderCompiler dependency) and run shader_compiler_test + processing_dispatch_test to completion."
    expected: "All 6 shader_compiler_test cases and all 7 processing_dispatch_test cases (including the 3 new ones: RenderPassValidGlslShadersCompileAndValidateEndToEnd, RenderPassMalformedGlslShaderFailsCompileNotCrash, RenderPassInvalidDirectSpirvFailsValidationNotCrash) pass when actually compiled and executed against a real link of ProcessingManager.cpp + shader_compiler.cpp."
    why_human: "Plan 02-04's own SUMMARY discloses that a full MSBuild/link build was not possible in this working tree (thirdparty/build/Windows/Debug lacks installed vk-bootstrap/shaderc/SPIRV-Tools artifacts) and substituted an MSVC `cl.exe /Zs` syntax+semantic-only check (no codegen, no link, no execution). The three new end-to-end dispatch tests that are supposed to prove SHADER-01/02/03 work through the real ProcessingManager::Process() path were never actually compiled or run — only grep/syntax-checked. This is a state-transition/behavioral claim (dispatch reaches ShaderCompiler, compiles/validates, returns the right Error) that cannot be confirmed by reading source code alone."
  - test: "Submit a job JSON with a legacy `shader_stage.type: \"hlsl\"` (or `\"metal\"`) value to `ProcessingManager::Create()` and confirm it returns `outcome::failure(Error::INVALID_JSON)` rather than crashing/propagating an uncaught exception."
    expected: "Create() returns a clean INVALID_JSON failure; process does not crash/abort."
    why_human: "The newly-added `catch ( const std::exception &e )` block in Init() (ProcessingManager.cpp lines 172-180) is code-reviewed as correct (more-derived-first ordering preserved, matches the documented quicktype `std::runtime_error`-on-enum-mismatch behavior) but no test in this phase actually exercises it with a schema-invalid enum value through a live `Create()` call. This is exactly the crash-prevention invariant the plan's own must_haves called out as a 'previously-live crash vector' — presence of a catch block does not by itself prove the exception path is reached and handled correctly at runtime."
  - test: "Confirm SGShaderCompiler links cleanly against the real production `shaderc::shaderc`/`SPIRV-Tools::SPIRV-Tools` targets inside the actual (not scratch/parallel) `thirdparty/build/Windows/Debug` tree, and that `ProcessingBase` (which now depends on `SGShaderCompiler`) configures/builds without errors."
    expected: "cmake --build succeeds for ProcessingBase, shader_compiler_test, and processing_dispatch_test targets in the project's real build tree."
    why_human: "Both 02-03 and 02-04 performed their real build verification in ephemeral scratch directories (MinGW+Ninja, outside the project's actual MSVC build tree) because the real build tree's vendored dependencies were not present this session. The MSVC .vcxproj build has never actually linked the new ShaderCompiler-dependent code in this working tree."
---

# Phase 2: Schema Extension & Shader/SPIR-V Validation Pipeline Verification Report

**Phase Goal:** The processing schema can fully describe a render pass, and every piece of SPIR-V that could reach the GPU — compiled from job-supplied GLSL or submitted directly — is validated before it ever reaches the driver.
**Verified:** 2026-07-31T00:17:03Z
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Schema (`gnus-processing-schema.json`) can declare render_target (color+depth format/dims/clear values), a multi-stage vertex+fragment shader array, vertex/index buffer bindings, and pipeline state (SCHEMA-01..04) | ✓ VERIFIED | Read schema directly: `render_target` (6 required fields, no defaults, matches D-15), `render_shader_config`/`shader_stage` (D-11/D-12), `vertex_layout_entry`+`vertex_buffer` (D-16/D-16 Amendment, `source` regex-constrained, required), `index_buffer` (D-17, configurable `index_type`), `pipeline_state` (D-13/D-14, 4 fields w/ defaults, no `depth_compare_op`). `pass.allOf`'s render branch requires `["render_shader","render_target","vertex_buffer"]`. |
| 2 | Schema is consumable through quicktype-regenerated headers with zero hand-edits; no stale orphaned headers remain (SCHEMA-05) | ✓ VERIFIED | `node -e "JSON.parse(...)"` → `VALID` (independently re-run). All 8 new generated headers present (`RenderShaderConfig.hpp`, `ShaderStage.hpp`, `RenderTarget.hpp`, `VertexLayoutEntry.hpp`, `VertexBuffer.hpp`, `IndexBuffer.hpp`, `PipelineState.hpp`, `ShaderSourceType.hpp`). `ShaderType.hpp`/`Uniform.hpp` confirmed absent from `generated/`, and zero references to `sgns::ShaderType`/`sgns::Uniform` remain outside `generated/`. `Pass.hpp` exposes all 6 new `boost::optional` accessors exactly as claimed. Test fixture schema copy is byte-identical (`diff` clean). |
| 3 | `ShaderCompiler` standalone component compiles GLSL to SPIR-V via vendored shaderc, with zero VkInstance/device dependency (SHADER-01) | ✓ VERIFIED | `shader_compiler.hpp`/`.cpp` read directly — no `VkInstance`/`VkDevice`/`VkPhysicalDevice` symbol anywhere. Backed by a **real** from-source MinGW+Ninja build (02-03) that compiled+linked the actual unmodified production files and ran 6 real GoogleTest cases, all passing (225/102-word validated SPIR-V modules produced). |
| 4 | Every piece of SPIR-V (GLSL-compiled or directly-submitted) passes a mandatory `spvtools::SpirvTools::Validate()` gate before being considered usable, at the `ShaderCompiler` component level (SHADER-02, SHADER-03) | ✓ VERIFIED | `grep -c "\.Validate("` on `shader_compiler.cpp` = 2 (both branches inline their own call, structurally impossible to bypass). Directly confirmed by reading the file: GLSL path and direct-SPIR-V path both construct `spvtools::SpirvTools` and call `.Validate()` before returning success. `MutatedValidSpirvFailsValidation` test (real, run, passing) proves a shaderc-produced-then-corrupted module is still rejected — the exact Pitfall 2 scenario. |
| 5 | `shader_stage.type`/`shader_config.type` narrows to `["glsl","spirv"]` only; `spirv` is explicitly accepted for render passes (SHADER-03) | ✓ VERIFIED | `grep -c '"metal"\|"hlsl"'` on schema = 0. `shader_source_type` enum = `["glsl","spirv"]`, shared via `$ref` by both `shader_config.type` and `shader_stage.type`. Generated `ShaderSourceType.hpp` enum = `{GLSL, SPIRV}`. |
| 6 | `ProcessingManager::CheckProcessValidity()` rejects a render pass missing `render_shader`/`render_target`/`vertex_buffer`/non-empty `vertex_layout` | ✓ VERIFIED | Code read directly at `ProcessingManager.cpp:216-239` — four sequential checks present, exact idiom match (`m_logger->error(...); return outcome::failure(Error::PROCESS_INFO_MISSING);`), matching plan spec exactly. This is deterministic branching logic (not a hidden state-transition), and its shape is unambiguous from source; the pre-existing `RenderPassMissingShaderFailsValidity`/`RenderPassValidPassesCheckProcessValidity` tests exercise this same call path structurally (though see note on build/run status below). |
| 7 | `ProcessingManager::GetCidForProc()` fetches, compiles, and validates every render-pass shader stage via `ShaderCompiler` **before returning success, through the real job-processing path** (not just standalone `ShaderCompiler` unit tests) — proven by a passing `RenderPassValidGlslShadersCompileAndValidateEndToEnd` dispatch test | ✓ VERIFIED (post-UAT) | Real MSVC build+run in `SuperGenius/build/Windows/Release`. Test passes with real log evidence of both stages compiling+validating before the deliberate missing-render-input failure. **A dangling-reference bug was found and fixed during this verification**: `stages` was bound as a reference through a temporary `get_render_shader().value()`, so the loop iterated zero times regardless of input — see 02-UAT.md item 1. |
| 8 | Malformed GLSL / invalid direct SPIR-V submitted through a real render-pass job fail with `SHADER_COMPILE_FAILED`/`SPIRV_VALIDATION_FAILED` (never a crash), through the real dispatch path | ✓ VERIFIED (post-UAT) | Real build+run: `RenderPassMalformedGlslShaderFailsCompileNotCrash` and `RenderPassInvalidDirectSpirvFailsValidationNotCrash` both pass, with real log evidence (`GLSL compile failed: shader:8: error: ... syntax error`, `Invalid SPIR-V magic number`) proving the actual malformed/invalid fixture content was compiled/validated and correctly rejected — not the pre-fix false pass caused by the dangling-reference bug. |
| 9 | A previously-live crash vector is closed: `Create()`'s JSON parsing survives a `std::runtime_error` thrown by the narrowed `ShaderSourceType` enum's `from_json` (e.g. a legacy `hlsl`/`metal` submission), returning `Error::INVALID_JSON` instead of propagating an uncaught exception | ✓ VERIFIED (post-UAT) | New permanent test `LegacyHlslShaderTypeFailsCleanlyNotCrash` submits a real fixture JSON with `shader_stage.type: "hlsl"` through a live `Create()` call — passes, returns `Error::INVALID_JSON`, no crash. |

**Score:** 9/9 truths verified (post-UAT re-verification — see reverification_note in frontmatter and 02-UAT.md)

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `SuperGenius/SGProcessingManager/gnus-processing-schema.json` | Fixed JSON bug + 8 new definitions + 6 new `pass` properties | ✓ VERIFIED | Parses valid; all definitions present; `hlsl`/`metal` fully removed |
| `SuperGenius/SGProcessingManager/generated/Pass.hpp` | 6 new `boost::optional` accessors | ✓ VERIFIED | All 6 present (`render_shader`, `render_target`, `vertex_layout`, `vertex_buffer`, `index_buffer`, `pipeline_state`) |
| `SuperGenius/SGProcessingManager/generated/RenderTarget.hpp` | 6 plain (non-optional) required members | ✓ VERIFIED | Confirmed: `clear_color`, `clear_depth`, `color_format`, `depth_format`, `height`, `width` all plain |
| `SuperGenius/SGProcessingManager/generated/VertexBuffer.hpp` | Plain required `source` member | ✓ VERIFIED | Confirmed plain, regex-constrained |
| `thirdparty/.gitmodules` + submodules | shaderc/SPIRV-Tools/SPIRV-Headers pinned | ✓ VERIFIED | `git submodule status` shows clean (non-`-`) checkouts at pinned commits (`ff84893`/`01c8438e`/`2a9b6f95`) |
| `thirdparty/build/CommonTargets.cmake` | `shaderc::shaderc`, `SPIRV-Tools::SPIRV-Tools` targets | ✓ VERIFIED | Both targets defined; real local build+install spike (documented in 02-02-SUMMARY) confirmed installed artifact paths |
| `SuperGenius/SGProcessingManager/include/shaders/shader_compiler.hpp` + `src/shaders/shader_compiler.cpp` | `ShaderCompiler` class, `CompileAndValidate()`, `Error` enum | ✓ VERIFIED | Read directly; matches spec exactly; both Validate() call sites present |
| `SuperGenius/test/src/shader_compiler/shader_compiler_test.cpp` | 6 `TEST_F` cases | ✓ VERIFIED | All 6 present by name; content matches the plan's intended coverage (GLSL vertex/fragment happy path, malformed-GLSL rejection, direct-SPIR-V round-trip, invalid-bytes rejection, mutated-valid-SPIR-V rejection). Real-build-verified (02-03) in a parallel from-source spike. |
| `SuperGenius/SGProcessingManager/src/processingbase/ProcessingManager.cpp`/`.hpp` | `Error::SHADER_COMPILE_FAILED`/`SPIRV_VALIDATION_FAILED`, extended `CheckProcessValidity()`, rewired `GetCidForProc()`, broadened `Init()` catch | ✓ VERIFIED (presence/wiring) — ⚠️ (behavior, see truths 7-9) | Code present, correct by inspection, links `SGShaderCompiler` in CMakeLists.txt. Full build/link/run not performed this session (self-disclosed gap). |
| `SuperGenius/test/src/processing_dispatch/processing_dispatch_test.cpp` | 7 `TEST_F` cases (4 existing + 3 new) | ✓ VERIFIED (presence) — ⚠️ (never executed) | All 7 present by name with correct assertions by inspection; never compiled/run this session. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| `Pass::get_render_shader()`/`get_render_target()`/`get_vertex_buffer()`/`get_vertex_layout()` | `ProcessingManager::CheckProcessValidity()` | Direct accessor calls | ✓ WIRED | Confirmed in source at `ProcessingManager.cpp:216-239` |
| `ShaderConfig::get_type()`/`ShaderStage::get_type()` | Shared `sgns::ShaderSourceType` enum | `$ref` in schema, generated headers | ✓ WIRED | Both confirmed sharing the same enum type in generated headers |
| `shaderc::shaderc`/`SPIRV-Tools::SPIRV-Tools` (CMake targets) | `SGShaderCompiler` (`src/shaders/CMakeLists.txt`) | `target_link_libraries` | ✓ WIRED | `grep -c` confirms both present |
| `SGShaderCompiler` | `ProcessingBase` (`src/processingbase/CMakeLists.txt`) | `target_link_libraries` | ✓ WIRED (declared) — ⚠️ (never actually linked this session) | Present in CMakeLists.txt; full CMake configure/build of ProcessingBase against this new dependency has not been performed in this working tree |
| `ProcessingManager::GetCidForProc()` | `sgns::sgprocessing::ShaderCompiler::CompileAndValidate()` | Direct call, per-stage loop | ✓ WIRED (code) — ⚠️ (behavior unverified) | Confirmed in source at `ProcessingManager.cpp:996-1007` |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| SCHEMA-01 | 02-01, 02-04 | render-target/framebuffer config | ✓ SATISFIED | `render_target` definition + `CheckProcessValidity()` presence check |
| SCHEMA-02 | 02-01, 02-04 | vertex/index buffer bindings + layout | ✓ SATISFIED | `vertex_buffer`/`vertex_layout_entry`/`index_buffer` definitions + presence checks |
| SCHEMA-03 | 02-01, 02-04 | multi-stage (vertex+fragment) shader pipeline | ✓ SATISFIED | `render_shader_config`/`shader_stage` (D-11 Amendment: sibling property, not re-typed `shader`) |
| SCHEMA-04 | 02-01, 02-04 | pipeline state (topology/cull/winding/depth-test) | ✓ SATISFIED | `pipeline_state` definition, curated v1 subset (D-13/D-14) |
| SCHEMA-05 | 02-01 | quicktype regeneration, zero hand-edits | ✓ SATISFIED | Regeneration confirmed, orphans deleted, fixture synced |
| SHADER-01 | 02-02, 02-03, 02-04 | GLSL compiled to SPIR-V in-process via vendored shaderc, at job-load time, before any GPU call | ✓ SATISFIED (component) — ⚠️ (end-to-end dispatch behavior unverified, see truths 7-9) | shaderc vendored + real build-verified; `ShaderCompiler` real-build-verified; `GetCidForProc()` wiring present but not run |
| SHADER-02 | 02-02, 02-03, 02-04 | mandatory `spirv-val` gate on all SPIR-V before `vkCreateShaderModule` | ✓ SATISFIED (component) — ⚠️ (end-to-end dispatch behavior unverified) | Same as above |
| SHADER-03 | 02-01, 02-03, 02-04 | `shader_config.type: "spirv"` accepted for render passes (reinterpreted as `shader_stage.type` per D-11 Amendment), subject to validation | ✓ SATISFIED | Schema-level narrowing + `ShaderCompiler`'s direct-SPIR-V path, both real-tested |

No orphaned requirements — all 8 IDs in REQUIREMENTS.md's Phase 2 traceability table are claimed by at least one plan's `requirements` frontmatter, matching the phase task's stated requirement list exactly.

### Anti-Patterns Found

None. Scanned all newly-created/modified core files (`shader_compiler.hpp/.cpp`, `ProcessingManager.hpp/.cpp`, `gnus-processing-schema.json`) for `TODO`/`FIXME`/`XXX`/`TBD`/`HACK`/`PLACEHOLDER`/stub patterns — zero matches.

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Schema is valid JSON | `node -e "JSON.parse(...)"` | `VALID` | ✓ PASS |
| No `hlsl`/`metal` remain in schema | `grep -c '"metal"\|"hlsl"'` | `0` | ✓ PASS |
| Test fixture schema copy in sync | `diff` source vs. fixture | clean (identical) | ✓ PASS |
| Orphaned generated headers removed | `ls generated/ShaderType.hpp generated/Uniform.hpp` | absent | ✓ PASS |
| No stray `sgns::ShaderType`/`sgns::Uniform` references | `grep -rn` outside `generated/` | zero matches | ✓ PASS |
| Both `.Validate()` call sites present in `shader_compiler.cpp` | `grep -c "\.Validate("` | `2` | ✓ PASS |
| Submodule commits exist and are referenced by parent checkouts | `git cat-file -t <hash>` x12, `git ls-tree HEAD` | all resolve as `commit`, pointers match working HEADs | ✓ PASS |
| Full build/test execution of ProcessingManager + shader_compiler_test + processing_dispatch_test | N/A | N/A | ? SKIP — no runnable build tree available this session (multi-submodule CMake project with no root-level build/test command per this project's documented constraint); this is exactly the gap plan 02-04's own SUMMARY flags and recommends closing before Phase 3 |

### Probe Execution

No `scripts/*/tests/probe-*.sh` convention exists in this repository and none were declared in this phase's PLAN/SUMMARY files. Step 7c: SKIPPED (no probes declared or discovered).

### Human Verification Required (RESOLVED — see 02-UAT.md)

All 3 items below were resolved via real build+run during post-verification follow-up
(2026-07-31T21:20:00Z). See `reverification_note` in frontmatter and `02-UAT.md` for full
evidence. Original items preserved below for record:

1. **Full build+link+run of `ProcessingBase` (with new `SGShaderCompiler` dependency), `shader_compiler_test`, and `processing_dispatch_test`.** This is the single most consequential open item: every claim about SHADER-01/02/03 being wired into the *real* job-processing path (`ProcessingManager::GetCidForProc()`) rests on code that was written correctly per inspection and syntax-checked with MSVC `cl.exe /Zs`, but has never actually been compiled, linked, or executed in this working tree. The `ShaderCompiler` component itself (`shader_compiler.hpp`/`.cpp`) *was* real-build-verified via a from-source MinGW+Ninja spike (02-03) with 6 passing tests — that part is solid. The gap is specifically in 02-04's wiring layer.
2. **Exercise the newly-added exception-safety catch clause** (`Init()`'s broadened `catch (const std::exception&)`) with an actual legacy `hlsl`/`metal` job submission, to confirm the previously-live crash vector is truly closed at runtime, not just in code review.
3. **Confirm `SGShaderCompiler` actually links** against the real (not scratch/parallel) `shaderc::shaderc`/`SPIRV-Tools::SPIRV-Tools` targets inside this project's actual MSVC build tree.

### Gaps Summary

No functional defects, missing artifacts, or broken key links were found — every artifact this phase claims to have produced actually exists, is substantive (not a stub), and is wired correctly by direct source inspection. The schema-level work (plan 02-01), the vendoring work (plan 02-02), and the standalone `ShaderCompiler` component (plan 02-03) all carry **real, executed, from-source build verification** with passing tests, which is unusually strong evidence for a phase in a project with no unified build/test command.

The one genuine, self-disclosed gap is in plan 02-04: the `ProcessingManager` wiring layer that completes the phase goal's "before it ever reaches the driver" guarantee through the actual job-processing path was verified only via a syntax-only (`cl.exe /Zs`, no codegen/link) check, not an actual build+run. The three new end-to-end dispatch tests that were specifically written to prove this wiring (`RenderPassValidGlslShadersCompileAndValidateEndToEnd`, `RenderPassMalformedGlslShaderFailsCompileNotCrash`, `RenderPassInvalidDirectSpirvFailsValidationNotCrash`) have never actually been executed. This is precisely a behavior-dependent claim (dispatch reaches the compiler, compiles/validates, and returns the correct `Error` value) that cannot be confirmed by code reading alone — it is routed to human verification rather than marked FAILED, since there is no evidence of an actual defect, only unexecuted evidence.

Recommendation (matching plan 02-04's own SUMMARY): perform a full from-scratch build+link+test pass (or a from-source spike matching 02-03's own precedent) before or early in Phase 3, since Phase 3's `RenderProcessor` will depend directly on `mainbuffers->first`'s `SerializeCompiledStages()` wire format and on `GetCidForProc()`'s render-pass branch actually working at runtime.

---

*Verified: 2026-07-31T00:17:03Z*
*Verifier: Claude (gsd-verifier)*
