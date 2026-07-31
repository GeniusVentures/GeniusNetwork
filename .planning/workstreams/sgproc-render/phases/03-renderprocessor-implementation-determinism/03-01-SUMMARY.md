---
phase: 03-renderprocessor-implementation-determinism
plan: 01
subsystem: SGProcessingManager (ProcessingManager / ProcessingResult)
tags: [error-handling, dispatch-gate, spir-v, wire-format, vulkan]
dependency-graph:
  requires: []
  provides:
    - ProcessingResult::error (std::optional<ProcessingError>)
    - ProcessingErrorStage enum (12 values)
    - ProcessingManager::Error::PROCESSING_FAILED
    - SerializeCompiledStages(stages, entryPoints) two-parameter wire format
  affects:
    - SuperGenius/SGProcessingManager/include/processors/processing_processor.hpp
    - SuperGenius/SGProcessingManager/include/processingbase/ProcessingManager.hpp
    - SuperGenius/SGProcessingManager/src/processingbase/ProcessingManager.cpp
tech-stack:
  added: []
  patterns:
    - "std::optional<Error> struct field on a concrete-return-type DTO instead of outcome::result<> plumbing (matches D-25's no-signature-change constraint)"
    - "Length-prefixed UTF-8 string field appended to an existing little-endian packed wire format"
key-files:
  created: []
  modified:
    - SuperGenius/SGProcessingManager/include/processors/processing_processor.hpp
    - SuperGenius/SGProcessingManager/include/processingbase/ProcessingManager.hpp
    - SuperGenius/SGProcessingManager/src/processingbase/ProcessingManager.cpp
decisions:
  - "ProcessingErrorStage/ProcessingError are plain (non-outcome::result) types, matching D-25's explicit 'no StartProcessing() signature change' constraint -- StartProcessing() keeps returning the concrete ProcessingResult, not outcome::result<ProcessingResult>, so the OUTCOME_HPP_DECLARE_ERROR_2 machinery would be unnecessary ceremony here."
  - "D-28's MNN retroactive fix is satisfied by treating an empty ProcessingResult::hash as an additional failure signal alongside the new error field -- zero changes to any of the 15 MNN processor files, since every one of their existing failure returns already leaves hash as a default-constructed empty vector."
metrics:
  duration: ~35min
  completed: 2026-07-31
status: complete
---

# Phase 3 Plan 1: ProcessingResult Error Field + Dispatch Gate + SPIR-V Wire Format Summary

Added a structured, per-stage `ProcessingResult::error` field and a uniform `ProcessingManager::Process()` failure gate covering both the future render path and the existing MNN path, and closed the SPIR-V wire-format gap that was dropping each shader stage's `entry_point` string.

## What Was Built

**Task 1 — `ProcessingResult::error` (D-25/D-26) + `ProcessingManager::Error::PROCESSING_FAILED`**

- `processing_processor.hpp` gained `enum class ProcessingErrorStage` (12 enumerators: `UNSPECIFIED`, `CONTEXT_INIT_FAILED`, `RESOURCE_RESOLUTION`, `BUFFER_ALLOCATION`, `IMAGE_ALLOCATION`, `FORMAT_UNSUPPORTED`, `SHADER_MODULE_CREATION`, `PIPELINE_CREATION`, `RENDER_PASS_CREATION`, `DRAW_SUBMISSION`, `READBACK`, `DATA_TRANSFORM_UNSUPPORTED`) and `struct ProcessingError { ProcessingErrorStage stage; std::string message; }`.
- `ProcessingResult` gained `std::optional<ProcessingError> error` (additive, placed after `output_locations`; `hash`/`output_buffers`/`output_locations` unchanged).
- `ProcessingManager::Error` gained `PROCESSING_FAILED = 9`, with a matching `OUTCOME_CPP_DEFINE_CATEGORY_3` switch arm ("Processor failed to produce a valid result").

**Task 2 — `Process()` failure gate (D-27/D-28) + `SerializeCompiledStages` entry_point extension (Pitfall 6)**

- `SerializeCompiledStages` now takes `(stages, entryPoints)` and packs a length-prefixed entry-point string per stage (see Wire Format below). Guards against a stages/entryPoints size mismatch by returning an empty vector (a this-plan call-site invariant, not job-supplied input).
- `GetCidForProc()`'s render-branch stage-compile loop builds a parallel `std::vector<std::string> entryPoints` (the same `stage.get_entry_point().value_or("main")` expression already passed into `CompileAndValidate`) and passes it to `SerializeCompiledStages`.
- `Process()` now checks `processResult.error || processResult.hash.empty()` immediately after `StartProcessing()` returns, before the `output_buffers`/save-loop block, logging the structured message (or a legacy-sentinel message for the empty-hash case) and returning `outcome::failure(Error::PROCESSING_FAILED)` instead of falling through to `FileManager::SaveASync`. This single insertion covers both the render path (future `error` field usage, wired by plans 03-03/03-05) and the existing MNN path (via the pre-existing empty-hash convention) with zero changes to any of the 15 MNN processor files.

## Final Wire Format (for plan 03-03's `RenderProcessor` parser to reference verbatim)

All integers little-endian, native `uint32_t` width:

```
uint32_t stage_count
per stage:
  uint32_t stage_tag        (static_cast<uint32_t>(sgns::Stage))
  uint32_t entry_point_len  (number of following raw UTF-8 bytes)
  entry_point_len raw UTF-8 bytes (NO null terminator)
  uint32_t word_count       (number of following uint32_t SPIR-V words)
  word_count * uint32_t spirv_words
```

This is the exact byte-for-byte format `RenderProcessor`'s inverse parser (plan 03-03) must implement — `entry_point` sits between `stage_tag` and `word_count`.

## Verification

- `grep -c "ProcessingErrorStage\|ProcessingError\b" processing_processor.hpp` → 4 (enum def, struct def, struct member reference, field type reference) — satisfies Task 1's `>= 1` acceptance gate.
- `grep -c "PROCESSING_FAILED" ProcessingManager.cpp` → 1 (the new switch arm).
- `grep -c "processResult.error || processResult.hash.empty()"` → 1 (gate appears exactly once, positioned between `StartProcessing()` and the save-loop).
- **Full CMake link-build succeeded** in this working tree for both `ProcessingBase` and `processing_dispatch_test` targets (`cmake --build "W:/gnus/GeniusNetwork/SuperGenius/build/Windows/Release" --target <target> --config Release`) — this resolves STATE.md's carried-forward Blocker ("Phase 02's full MSBuild link-build was never verified end-to-end in this working tree"); a real installed build tree with vk-bootstrap/shaderc/SPIRV-Tools already exists and links cleanly. No `cl.exe /Zs` syntax-only fallback was needed this plan.
- Ran `processing_dispatch_test.exe --gtest_filter="*RenderPass*"`: 5/6 pass. `RenderPassValidGlslShadersCompileAndValidateEndToEnd` fails, but this failure was confirmed **pre-existing** (identical failure, same enum value, same log output) by stashing Task 2's edits and re-running against Task-1-only state — see Deviations below and `deferred-items.md`.

## Deviations from Plan

### Auto-fixed Issues

None — plan executed exactly as written for both tasks; no Rule 1/2/3 auto-fixes were needed.

### Out-of-Scope Discovery (logged, not fixed)

**DI-03-01-01: `RenderPassValidGlslShadersCompileAndValidateEndToEnd` fails, pre-existing, unrelated to this plan's changes.**
- Found during Task 2's verification run (the first full link+run of `processing_dispatch_test` in this working tree, per STATE.md's carried-forward blocker).
- The test expects `Process()` to fail with `INPUT_UNAVAIL` after both real GLSL fixture shaders compile+validate successfully, but it fails with `SHADER_COMPILE_FAILED` — the `ShaderCompiler` log shows a `#version 110`-style default-compile error despite both fixtures declaring `#version 450`. Preceding `Failed to obtain processing source: File could not be opened` log lines indicate the `file://processing_dispatch/dummy_shader.glsl`/`dummy_fragment_shader.glsl` fixture URLs are not resolving in this test run's working directory, so an empty/fallback buffer is what's reaching `shaderc`, not the actual fixture source.
- **Confirmed out of scope for this plan**: stashing Task 2's `ProcessingManager.cpp` edits and re-running the identical test against Task-1-only state reproduces the exact same failure (same enum value `7`/`SHADER_COMPILE_FAILED`, same log messages) — proving this plan's `SerializeCompiledStages`/`Process()` gate changes neither cause nor interact with it.
- Logged in full at `.planning/workstreams/sgproc-render/phases/03-renderprocessor-implementation-determinism/deferred-items.md` (DI-03-01-01) with a root-cause hypothesis (test-fixture working-directory-relative `file://` URL resolution) for a future plan to investigate, since 03-02+'s own render-pass fixtures will hit the same resolution path.

### Auth Gates

None encountered.

## Self-Check: PASSED

- `SuperGenius/SGProcessingManager/include/processors/processing_processor.hpp` — FOUND
- `SuperGenius/SGProcessingManager/include/processingbase/ProcessingManager.hpp` — FOUND
- `SuperGenius/SGProcessingManager/src/processingbase/ProcessingManager.cpp` — FOUND
- Commit `a64e6f1` (SGProcessingManager, Task 1) — FOUND
- Commit `b358ebd` (SGProcessingManager, Task 2) — FOUND
- Commit `375ced9d` (SuperGenius, Task 1 pointer bump) — FOUND
- Commit `2ebddae1` (SuperGenius, Task 2 pointer bump) — FOUND
- Commit `a336f0d` (GeniusNetwork, Task 1 pointer bump) — FOUND
- Commit `a807153` (GeniusNetwork, Task 2 pointer bump) — FOUND
