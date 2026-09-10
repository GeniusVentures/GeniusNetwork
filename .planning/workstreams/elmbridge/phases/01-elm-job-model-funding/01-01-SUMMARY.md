---
phase: 01-elm-job-model-funding
plan: 01
status: completed
started: 2026-09-10T02:00:00Z
completed: 2026-09-10T04:45:00Z
---

# Plan 01-01 Summary: ELM Job Schema in SGProcessingManager

## What Was Built

The ELM job contract landed in SGProcessingManager: `job_type`/`elms[]`/`generation`/`funding`/`validation` in `gnus-processing-schema.json`, quicktype regen (zero hand edits to `generated/`), C++ parse gates for everything quicktype cannot enforce, default-fill normalization via one accessor, and the full 27-case parse-rejection test matrix.

### Tasks Completed

| Task | Description | Commit |
|------|-------------|--------|
| 1 | ELM schema block + quicktype regen (root required relaxed to name/version/gnus_spec_version per D-04; Elm/ElmGeneration/ElmFunding definitions; job_type/validation enums) | `882ab95` |
| 1-fix | Compile shims for schema-optional passes/inputs/outputs across 12+ call sites | `fb7b744` |
| 2 | Error enum 14-18, `CheckElmValidity` gates, non-ELM parity gate in Init, `GetElmMaximumProcessingHours` | `a26b9de` |
| 3 | 27-case test matrix `sgprocbase_elm_job_schema_test` + CMake registration + critical optional-lifetime fixes | `97bbd04` |

### Key Files

- `SuperGenius/SGProcessingManager/gnus-processing-schema.json` — ELM block (job_type enum `[elm_processing]`, elms[] with work_item_id pattern `^[A-Za-z0-9_-]+$`, ElmGeneration bounds, ElmFunding 0..24h cap, validation enum `[none,exact,redundant]`)
- `SuperGenius/SGProcessingManager/generated/` — regenerated: `Elm.hpp`, `ElmGeneration.hpp`, `ElmFunding.hpp`, `ElmType.hpp`, `JobType.hpp`, `Validation.hpp` + updated root/Pass/etc.
- `SuperGenius/SGProcessingManager/include/processingbase/ProcessingManager.hpp` — Error enum 14-18, public `GetElmMaximumProcessingHours()`, private `CheckElmValidity()`
- `SuperGenius/SGProcessingManager/src/processingbase/ProcessingManager.cpp` — gates, parity gate, accessor, optional-lifetime discipline
- `SuperGenius/SGProcessingManager/test/processingbase/` — new test dir (27 cases, gated discovery)

## Generated Type Spellings (recorded for plans 01-02/01-03)

- `sgns::JobType::ELM_PROCESSING`, `sgns::ElmType::CAUSAL_LM`
- `sgns::Validation::NONE`/`EXACT`/`REDUNDANT` — enum class named **`Validation`**, NOT `ElmValidationMode` as the plan guessed (quicktype derives the name from the property)
- `sgns::Elm`, `sgns::ElmGeneration` (`int64_t` max_output_tokens/seed, `double` temperature/top_p), `sgns::ElmFunding` (`double` maximum_processing_hours)
- Root accessors: `get_job_type()`, `get_elms()`, `get_funding()`, `get_validation()`; `passes`/`inputs`/`outputs` now `boost::optional<std::vector<...>>`

## Requirements Addressed

- **JOB-01** (schema leg): ELM jobs express work items/funding/validation entirely in `Task.json_data`; zero `.proto` diffs (verified)
- **JOB-03** (schema-level validation-mode decision): full schema enum per D-13; `exact`/`redundant` parse but are refused by the C++ gate with `ELM_VALIDATION_UNIMPLEMENTED`
- **SC-1**: minimal ELM job parses; malformed jobs reject at Create with structured errors 14-18
- **SC-5**: non-ELM rejection outcomes unchanged (missing passes/inputs/outputs, empty passes → INVALID_JSON at the same entry point) and test-locked
- **D-04/D-05/D-06/D-07/D-13** implemented and test-pinned; D-06 honored (no new version field; `gnus_spec_version==1` constraint survives regen)

## Self-Check: PASSED

All acceptance criteria verified per task (greps + builds + test runs). Final state: `sgprocbase_elm_job_schema_test` 27/27 green; **all 15 SGProcessingManager test binaries exit 0** (artifact_serializer, capability_validator, capture_smoke, 7 execution tests, mnn_llm, mnn_tensor_fp4, diff_utils, quantization); full standalone Release build clean; `git diff` scoped review confirms no non-ELM error path changed beyond the added parity gate.

## Deviations from Plan

**[Rule 1 — Codegen reality] quicktype drops inclusive number bounds for OPTIONAL fields.** Found during: Task 1. The plan expected `min_double_value`/`max_double_value` to survive codegen in `ElmGeneration.hpp`; they did not (`boost::none` everywhere), while required-number `gnus_spec_version` keeps `(1,1)`. Verified consistent with all prior regens (Dimensions.batch, Pass.per_pass_deadline_ms identical). Fix: the C++ gate enforces ALL inclusive bounds (temperature [0,2], top_p (0,1], max_output_tokens ≥1, seed ≥0, funding hours (0,24]) — matching the plan's own A3 "C++ gate is authoritative" stance. Behavior matrix unchanged; only the enforcement point moved fully into `CheckElmValidity`.

**[Rule 1 — Missing critical] Schema-optional root vectors broke 12+ call sites.** Found during: Task 1 build. Relaxing root `required` made `passes`/`inputs`/`outputs` `boost::optional` in the regenerated root, breaking ProcessingManager.cpp (Init/CheckProcessValidity/ParseBlockSize/ProcessInternal/GetCidForProc) and `tools/capture/capture_harness.cpp`. Fix: compile-only `value_or(empty)` shims at each site (the Task 2 parity gate guarantees the optionals are engaged for every reachable non-ELM path; ELM jobs never reach Process in v1.0). Files: ProcessingManager.cpp, capture_harness.cpp. Verification: full build + all 15 test binaries. Commits `fb7b744`, `97bbd04`.

**[Rule 1 — Latent bug exposed by tests] quicktype getters return `boost::optional<T>` BY VALUE.** Found during: Task 3 test runs. `*data.get_elms()` / `*processing_.get_funding()` dereference a temporary that dies at end-of-expression — iteration was UB (observed: `size()==0` read from freed memory, gates silently skipping). Fix: every optional access in the new code paths materializes into a named local (`const auto elmsOpt = data.get_elms();`). Verification: dup/top_p/funding gates now fire; 27/27 green. This pattern did NOT exist in pre-change code (existing getters returned references/required values), so no existing-site audit was needed beyond the compile shims above.

**[Cosmetic] Validation enum spelling.** Plan expected `sgns::ElmValidationMode`; quicktype emitted `sgns::Validation` (named from the property). Recorded here and in commit `a26b9de` for plans 01-02/01-03.

**Total deviations:** 3 auto-fixed (1 codegen-reality acceptance, 2 Rule-1 code fixes). **Impact:** none on the behavior matrix — every must-have truth and SC-1/SC-5 outcome holds exactly as written; enforcement points shifted from (nonexistent) generated constraints to the C++ gate the plan already designated as authoritative.

## Issues Encountered

- The local build tree's `BUILD_TESTING` cache was configured OFF, so `ctest -R sgprocbase_elm_job_schema_test` reports "No tests were found" — ran the binary directly instead (exit 0). The `add_test`/discovery registration is correct for CI standalone builds.
- Multi-line C++ raw strings in the first test draft were corrupted on this CRLF checkout (composed JSON broke); switched to escaped-string concatenation. Test-only, no production impact.

## Next Phase Readiness

Plan 01-02 consumes: `GetElmMaximumProcessingHours()` (single defaulted read site), the SGProcessingManager pointer bump, and the recorded generated spellings above. No blockers.
