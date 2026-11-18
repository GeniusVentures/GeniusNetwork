---
status: testing
phase: 15-evidence-aware-cold-serving-forced-walk-recovery
source: [15-VERIFICATION.md]
started: 2026-11-17T00:00:00Z
updated: 2026-11-17T00:00:00Z
---

## Current Test

number: 1
name: CR-01 disposition — accept recorded deferral or require fix before sealing
expected: |
  A ruling on the one open Critical from 15-REVIEW.md (serve-side TOCTOU: a TxPruner
  erase committing between the evidence consult and Rehydrate resurrects erased bytes
  hot on the getNode/GetNodeWithoutRequest/re-warm surfaces until eviction). The
  reviewer's minimal patch (re-classify after the slow cold Get, before Rehydrate;
  same for the re-warm window) can land as a pre-Phase-16 quick task, or the fix is
  folded into Phase 16 (pruner×GC hardening) planning + Phase 19 TEST-02 repro.
  Either ruling is acceptable; the item exists so the Critical is consciously
  dispositioned, not silently absorbed.
awaiting: user response

## Tests

### 1. CR-01 disposition — accept recorded deferral or require fix before sealing
expected: Explicit user ruling: (a) accept deferral with the fix scheduled (Phase 16
  planning intake / pre-Phase-16 quick task), or (b) require the CR-01 fix to land
  before the phase is marked complete.
result: [pending]

### 2. Executor-push posture — backstop prohibition acknowledgment
expected: Acknowledgment that all phase-15 commits are local-only (nothing pushed),
  per the standing no-push rule for this repo. No violation evidence exists; this is
  the recorded confirmation that the local-commit posture was inspected and accepted.
result: [pending]

## Summary

total: 2
passed: 0
issues: 0
pending: 2
skipped: 0
blocked: 0

## Gaps
