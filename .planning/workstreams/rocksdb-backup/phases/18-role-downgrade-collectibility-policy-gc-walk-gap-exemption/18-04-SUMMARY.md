---
phase: 18-role-downgrade-collectibility-policy-gc-walk-gap-exemption
plan: 04
subsystem: documentation
tags: [policy, rulings-chain, collectibility, downgrade-interlock]

requires:
  - phase: 18-role-downgrade-collectibility-policy-gc-walk-gap-exemption
    provides: 18-01/02/03's committed evidence (red signature, verdict matrix, t0->t3 timeline) the record cites
provides:
  - notes/18-collectibility-policy-downgrade-interlock.md - the SC1 deliverable: the two-halves rule as one rulings document (permanent-cold policy + exemption record + interlock record + operator checklist + tiered-node model + timeline + v2 contract-ask sketch + options table + evidence)
  - the STATE.md POLICY-01/02 decision one-liner (the rulings-chain breadcrumb)
affects: [phase-19-capstone, sgns-blockstore-v2]

actuals:
  tokens: 9000
  tasks: 2
  commits: 2

tech-stack:
  added: []
  patterns: []

key-files:
  created:
    - .planning/workstreams/rocksdb-backup/notes/18-collectibility-policy-downgrade-interlock.md
  modified:
    - .planning/workstreams/rocksdb-backup/STATE.md

key-decisions:
  - "The record landed at the exact path the 18-01/18-02/18-03 code ruling comments cite - every citation resolves with zero code edits"
  - "No measurements section (unlike notes/17): this phase produces behavioral evidence - the Evidence section cites legs and signatures, not JSON"

patterns-established:
  - "Pattern: policy record with concrete-anchor resolution (every capability claim cites a suite/leg; every mechanism cites its landed symbols - ack key, fingerprint key, error code)"

requirements-completed: [POLICY-01]

coverage:
  - id: D1
    description: "The rulings doc: all seven content sections + the operator checklist + the options table + Evidence + Forward pointers, every claim resolving to committed evidence"
    requirement: POLICY-01
    verification:
      - kind: automated
        ref: "Source gates: sections=37 (>=12), anchors=13 (>=6: downgrade_acknowledged, /prune/role-fingerprint, HISTORY_PRUNED_LOCALLY, cold_gc_walk_gap_exempt_test, cold_downgrade_e2e_test, FP-DowngradeFire), header=6 (>=5), zero submodule diff"
        status: pass
    human_judgment: false
  - id: D2
    description: "The STATE.md one-liner: date-stamped verdict triad citing the record by path, additive-only"
    requirement: POLICY-01
    verification:
      - kind: automated
        ref: "Source gates: state-cite=1, state-verdict=1 ('POLICY-01/02 decided'), state-struct=3 (structural fields intact)"
        status: pass
    human_judgment: false

duration: 20min
completed: 2026-11-19
status: complete
---

# Phase 18 Plan 04: The Policy Record Summary

The two-halves rule is recorded as one document in the rulings chain - cold permanent this milestone, the exemption shipped as code, the interlock proven, the v2 ask sketched with preconditions - and every code-side citation lands at the exact path this record occupies.

## Performance

- **Duration:** 20 min
- **Tasks:** 2 / 2
- **Files:** 2 (1 new rulings doc, 1 STATE.md line)

## Tasks Completed

1. **The rulings doc** - `docs(18)` `19a9158`: notes/18-collectibility-policy-downgrade-interlock.md (header with context commits 84d87d462 -> 2c94e481b; sections (a)-(h); Evidence; Forward pointers).
2. **The STATE one-liner** - `docs(18)` `e1ec8c1`: the POLICY-01/02 decided bullet after the SEAL-01 line.

## Accomplishments

- SC1's deliverable complete: the recorded policy decision documents the permanent-cold policy, the permanent-once-written invariant, the v2 contract ask, AND the GC walk-gap exemption - in the same record
- The operator checklist has its canonical home (D-08); the WARN texts' path citations resolve
- The v2 sketch carries the require/why/preconditions triple with REQUIREMENTS Future cross-references; the shipped exemption is cited as satisfied precondition 1
- The options-considered-and-rejected table preserves all six-plus rejected alternatives
- Executor deviations from all three prior plans are recorded truthfully in the Evidence section (doc/code drift prevention)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## Next Phase Readiness

Phase 18 is complete (4/4 plans); all Tier-1 evidence green at 19/19. Ready for phase verification and the Phase 19 capstone.
