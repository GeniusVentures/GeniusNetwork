---
status: complete
phase: 10-capture-harness-diff-tool-quantization-stub
source: [10-VERIFICATION.md]
started: 2026-08-10T21:19:18Z
updated: 2026-08-11T21:40:00Z
---

## Current Test

[testing complete]

## Tests

### 1. capture_harness --repeat instability-abort path (D-05)
expected: capture_harness prints a message identifying which iteration and field diverged (contentHash/chunkHashCount/chunkHashes[j]/combinedHash), exits with a non-zero status, and writes no .cap file to --output-dir.
result: skipped
reason: User ran normal capture_harness runs (not a forced-failure scenario) and confirmed no code was temporarily patched to desync determinism. Exercising this path requires deliberately breaking determinism (e.g. patching QuantizeFloatBuffer to alternate output); deferred per user choice. 10-VERIFICATION.md already documents this as present-and-correctly-gated-by-inspection, non-blocking for Phase 11.

### 2. capture_harness CAPT-02 self-check mismatch-abort path
expected: SelfCheckCapturedBytes() prints which chunk/combined check failed, capture_harness exits non-zero, and writes no .cap file.
result: skipped
reason: Same deferral as Test 1 — requires deliberately desyncing captured bytes from the hashed bytes, not exercised. 10-VERIFICATION.md already documents this as present-and-correctly-gated-by-inspection, non-blocking for Phase 11.

## Summary

total: 2
passed: 0
issues: 0
pending: 0
skipped: 2
blocked: 0

## Gaps
