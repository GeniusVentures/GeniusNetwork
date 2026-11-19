---
phase: 17
review: 17-REVIEW.md
reviewed: 2026-11-19
dispositioned: 2026-11-19
counts:
  critical: 0
  major: 2
  minor: 7
  info: 5
status: issues_found
---

# Review Disposition — Phase 17

Advisory record (the code-review gate never blocks execution). One row per finding from `17-REVIEW.md`; every row defaults to `open` until triaged.

| ID | Severity | Finding (abridged) | Status | Notes |
|---|---|---|---|---|
| MAJ-01 | Major | Big-leg re-run after a completed/interrupted gated run hits `ASSERT_EQ(pass.seals, scale)` opaquely at the 10⁶ point (persistent grow root by design) | open | Re-run guidance exists (evidence README § Reproduce — delete the grow root); a precondition guard + recovery hint is the right forward fix |
| MAJ-02 | Major | RocksDB iterator status never checked in `RunEnumerationPass`/`ScanSealKeys` — a mid-scan I/O error truncates indistinguishably from end-of-data | open | Measurement-instrument hardening; add `it->status()` checks and fail loudly |
| MIN-01 | Minor | `EnvOr` (`strtoull`) accepts negative/wrapped input (`-1` → ULLONG_MAX) past the `ASSERT_GT` | open | Integer-only posture holds for well-formed input; add endptr/errno validation |
| MIN-02 | Minor | Teardown-on-failure gap: early ASSERT skips `TeardownGlobalDbStack` (live pubsub host leaks into later tests) | open | gtest fixture/RAII wrapper is the fix |
| MIN-03 | Minor | Evidence JSONs written inside live RocksDB DB dirs (incl. the never-wiped grow root) | open | Cosmetic/provenance; relocate emitters to a sibling `evidence/` dir in a follow-up |
| MIN-04..07 | Minor | (per 17-REVIEW.md) remaining minor rows | open | — |
| INFO-01..05 | Info | (per 17-REVIEW.md) informational rows | open | — |

**Verified-sound (no action):** all five phase invariants hold in the harness source; the `cold_compose_matrix_test` stability fix was independently confirmed against production code (the GC's mark-time read bypasses the state hook — the R3(a) re-scope pins the mechanically-guaranteed half); CMake registration is idiom-parity with the sibling block; `SuperGenius/src` zero-diff vs `741980f5d`.

**Suggested follow-up:** a `gsd-quick`-shaped fix pass for MAJ-01/MAJ-02 (+MIN-01/02 if cheap) — none block the phase's recorded evidence or verdict.
