---
phase: 05-fault-injection-three-tier-hardening
reviewed: 2026-10-22
reviewer: inline (execute-phase code_review_gate, Copilot sequential mode)
files_reviewed: 15
findings:
  critical: 0
  major: 0
  minor: 2
  info: 2
status: complete
---

# Phase 5 Code Review — Fault Injection & Three-Tier Hardening

Scope: every source file changed by plans 05-01/05-02/05-03 (labels+audit+CI, D-09 hook + crash matrix, fake seams + fault-matrix breadth), reviewed against the phase threat models (T-05-01..T-05-09) and the coding standard.

## Findings

| ID | Severity | File | Finding | Disposition |
|----|----------|------|---------|-------------|
| R-1 | minor | thirdparty/sgns-blockstore/src/LocalBlockStore.cpp | The D-09 hook's corruption write-back discards the RocksDB Put status (`(void)`). A failed write-back would surface as a confusing downstream assertion failure (corruption never landed) rather than at the seam. Test-only scaffolding whose failure is detectable by the proof it serves (StoredCorruptionSelfHeals fails loudly) — acceptable as designed; the Doxygen already binds the hook to TEST-ONLY use. | open (accepted) |
| R-2 | minor | thirdparty/sgns-blockstore/test/tier1_audit_check.cmake | The `::1` neutralizer regex (two-boundary form with backreference replacement) has no live positive case in the current tree (no `::1` literals exist in test sources) — it is exercised only by inspection, not by a passing test. The IPv4 neutralizer and all ban patterns ARE live-proven by the negative probes and the real-tree pass. | open (accepted) |
| I-1 | info | thirdparty/sgns-blockstore/src/InMemoryS3Client.cpp | `FaultFor` was extracted as a static mapper shared by the key overlay and the op table — behavior-preserving refactor of the prior switch, verified by the full fake/store/drainer suites. | resolved (by construction) |
| I-2 | info | thirdparty/.github/workflows/build.yml | `--no-tests=error` is unconditionally correct today (12 Tier1-labeled tests exist); if the label set were ever emptied, CI fails loudly rather than passing vacuously — exactly the intended fail-closed posture. | resolved (by construction) |

## Threat-model cross-check

- T-05-01/02 (CI lane tampering, audit allowlist): fail-closed `-L` + `--no-tests=error` + audit-as-ctest + count guard — four independent layers, all verified live (probes + lane run).
- T-05-04/05 (hook misfire, journal-CF touch): arming is member-default-false, TEST-ONLY documented, gated `!already_present`, writes only the blocks CF — pinned by FaultCorruptionDoesNotEvict + StoredCorruptionSelfHeals green.
- T-05-07/08 (matrix re-classification, bad-byte caching/deletion): layer-discipline grep green (no CidOf in the transport suite); re-fetch-still-Corrupt and ObjectKeys-never-deleted assertions green.
- T-05-09 + T-05-SC: fake seams carry CONFORMANCE-TEST SEAM docs; S3Client.hpp frozen (token-gated); zero package installs.

## Verdict

**0 critical / 0 major** — no blocking findings. The two minor items are recorded as accepted-open with rationale; neither affects the phase's must-have truths.
