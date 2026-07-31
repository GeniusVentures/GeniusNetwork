---
status: testing
phase: 02-schema-extension-shader-spir-v-validation-pipeline
source: [02-VERIFICATION.md]
started: 2026-07-31T00:20:00Z
updated: 2026-07-31T00:20:00Z
---

## Current Test

number: 1
name: Full build+link+run of ProcessingBase (with new SGShaderCompiler dependency), shader_compiler_test, and processing_dispatch_test
expected: |
  cmake --build succeeds for the ProcessingBase, shader_compiler_test, and processing_dispatch_test
  targets in the project's real (MSVC) build tree. All 6 shader_compiler_test cases and all 7
  processing_dispatch_test cases pass, including the 3 new ones:
  RenderPassValidGlslShadersCompileAndValidateEndToEnd,
  RenderPassMalformedGlslShaderFailsCompileNotCrash,
  RenderPassInvalidDirectSpirvFailsValidationNotCrash.
awaiting: user response

## Tests

### 1. Full build+link+run of ProcessingBase, shader_compiler_test, processing_dispatch_test
expected: All listed test cases pass when actually compiled, linked, and executed against a real link of ProcessingManager.cpp + shader_compiler.cpp in this project's actual build tree.
result: [pending]

### 2. Exercise the newly-added exception-safety catch clause with a legacy hlsl/metal job
expected: Submitting a job JSON with shader_stage.type: "hlsl" (or "metal") to ProcessingManager::Create() returns outcome::failure(Error::INVALID_JSON) rather than crashing or propagating an uncaught exception.
result: [pending]

### 3. Confirm SGShaderCompiler links against the real production targets in the actual build tree
expected: cmake --build succeeds for ProcessingBase against the real (not scratch/parallel) shaderc::shaderc / SPIRV-Tools::SPIRV-Tools targets inside thirdparty/build/Windows/Debug.
result: [pending]

## Summary

total: 3
passed: 0
issues: 0
pending: 3
skipped: 0
blocked: 0

## Gaps
