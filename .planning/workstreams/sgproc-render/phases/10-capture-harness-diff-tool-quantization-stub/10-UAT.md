---
status: testing
phase: 10-capture-harness-diff-tool-quantization-stub
source: [10-VERIFICATION.md]
started: 2026-08-10T21:19:18Z
updated: 2026-08-10T21:19:18Z
---

## Current Test

number: 1
name: capture_harness --repeat instability-abort path (D-05)
expected: |
  capture_harness prints a message identifying which iteration and field diverged
  (contentHash/chunkHashCount/chunkHashes[j]/combinedHash), exits with a non-zero
  status, and writes no .cap file to --output-dir.
awaiting: user response

## Tests

### 1. capture_harness --repeat instability-abort path (D-05)
expected: capture_harness prints a message identifying which iteration and field diverged (contentHash/chunkHashCount/chunkHashes[j]/combinedHash), exits with a non-zero status, and writes no .cap file to --output-dir.
result: [pending]

### 2. capture_harness CAPT-02 self-check mismatch-abort path
expected: SelfCheckCapturedBytes() prints which chunk/combined check failed, capture_harness exits non-zero, and writes no .cap file.
result: [pending]

## Summary

total: 2
passed: 0
issues: 0
pending: 2
skipped: 0
blocked: 0

## Gaps
