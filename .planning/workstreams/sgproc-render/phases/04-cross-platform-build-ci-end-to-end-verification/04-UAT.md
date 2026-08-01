---
status: testing
phase: 04-cross-platform-build-ci-end-to-end-verification
source: [04-VERIFICATION.md]
started: "2026-08-01T00:10:26.442Z"
updated: "2026-08-01T00:10:26.442Z"
---

## Current Test

number: 1
name: Confirm E2E-02 on real macOS/MoltenVK hardware via the first post-merge CI run
expected: |
  After this phase's changes are merged and CI runs against the actual self-hosted runner
  fleet, inspect the OSX matrix job's "Report GPU-gated render test skips (OSX)" step's
  $GITHUB_STEP_SUMMARY output, and separately check the raw xunit results for
  RenderPassSameNodeRepeatedExecutionProducesBitExactHash and
  RenderPassEndToEndProducesVerifiedOutputHash on that job.

  Either (a) both tests show PASSED — this positively demonstrates E2E-02, the render path
  genuinely executes on gv-OSX-Large's MoltenVK/Metal passthrough — or (b) both tests show
  SKIPPED with the "No usable Vulkan device" annotation, meaning the Tart VM has no GPU/Metal
  passthrough. Per D-32/D-34, outcome (b) is an expected/acceptable result of this phase's
  design (structurally identical to the anticipated Linux/Windows GPU-less case) and is not
  itself a defect — but it also means E2E-02 remains unconfirmed, and must not be treated as
  "done" just because the CI wiring exists.
awaiting: user response

## Tests

### 1. Confirm E2E-02 on real macOS/MoltenVK hardware via the first post-merge CI run
expected: See above — PASSED (E2E-02 confirmed) or SKIPPED with "No usable Vulkan device" (acceptable per D-32/D-34, but E2E-02 stays open)
result: [pending]

## Summary

total: 1
passed: 0
issues: 0
pending: 1
skipped: 0
blocked: 0

## Gaps
