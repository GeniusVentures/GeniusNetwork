---
status: complete
phase: 10-capture-harness-diff-tool-quantization-stub
source: [10-VERIFICATION.md]
started: 2026-08-10T21:19:18Z
updated: 2026-08-11T21:47:00Z
---

## Current Test

[testing complete]

## Tests

### 1. capture_harness --repeat instability-abort path (D-05)
expected: capture_harness prints a message identifying which iteration and field diverged (contentHash/chunkHashCount/chunkHashes[j]/combinedHash), exits with a non-zero status, and writes no .cap file to --output-dir.
result: pass
evidence: Temporarily patched QuantizeFloatBuffer (quantization.cpp) to perturb its output on every call after the first, forcing iteration 1 to diverge from iteration 0. Ran capture_harness --fixture-root SuperGenius/test/src --fixture processing_datatypes/float-processing-definition.json --label test-d05 --repeat 2 --output-dir caps/scratch-d05. Output: "capture_harness: instability detected -- iteration 1's chunkHashes[0] diverged from iteration 0's; aborting, no capture file written", exit code 1, zero .cap files written to the output dir. Patch reverted immediately after (git checkout), capture_harness rebuilt clean.

### 2. capture_harness CAPT-02 self-check mismatch-abort path
expected: SelfCheckCapturedBytes() prints which chunk/combined check failed, capture_harness exits non-zero, and writes no .cap file.
result: pass
evidence: Temporarily patched capture_harness.cpp's rawOutputCapture lambda to flip a byte in the recorded copy after capture (desyncing it from what production sha256() actually hashed). Ran the same MNN float fixture with --repeat 2. Output: "capture_harness: iteration 0 self-check failed -- re-hashed captured chunk 0 does not match artifact.chunkHashes[0]", exit code 1, zero .cap files written. Patch reverted immediately after (git checkout), capture_harness rebuilt clean.

## Summary

total: 2
passed: 2
issues: 0
pending: 0
skipped: 0
blocked: 0

## Gaps
