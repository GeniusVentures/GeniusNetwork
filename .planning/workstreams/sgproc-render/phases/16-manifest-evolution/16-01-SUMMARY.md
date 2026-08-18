---
phase: 16-manifest-evolution
plan: 01
subsystem: docs
tags: [requirements, roadmap, bookkeeping, sgproc-render]

# Dependency graph
requires:
  - phase: 16-manifest-evolution (16-CONTEXT.md)
    provides: D-01..D-08 rationale for ARTF-07/ARTF-08 "Won't implement" conclusion
provides:
  - REQUIREMENTS.md ARTF-07/ARTF-08 bullets and traceability rows corrected to "Won't implement — not applicable"
  - ROADMAP.md Phase 16 phase-list bullet, Goal, and Success Criteria corrected to describe only the ARTF-09/ARTF-10 scope this milestone actually delivers
affects: [16-02-PLAN.md, 16-03-PLAN.md]

# Tech tracking
tech-stack:
  added: []
  patterns: []

key-files:
  created: []
  modified:
    - .planning/workstreams/sgproc-render/REQUIREMENTS.md
    - .planning/workstreams/sgproc-render/ROADMAP.md

key-decisions:
  - "ARTF-07/ARTF-08 marked 'Won't implement — not applicable' (not 'deferred') in both REQUIREMENTS.md and ROADMAP.md, citing 16-CONTEXT.md D-01..D-08, per the phase discussion's explicit rejection of 'deferred' wording"
  - "ROADMAP.md Phase 16 Success Criteria renumbered from 4 items to 2 (former SC3/SC4 only); SC1 (Merkle)/SC2 (CDC) removed from the numbered list and replaced by a dedicated 'Won't implement' subsection immediately below, matching REQUIREMENTS.md's phrasing for cross-document consistency"
  - "Requirements line ('ARTF-07, ARTF-08, ARTF-09, ARTF-10'), Depends on, and Plans lines in ROADMAP.md left completely unchanged — all 4 IDs remain this phase's requirements regardless of implementation status"

patterns-established: []

requirements-completed: [ARTF-07, ARTF-08]

coverage:
  - id: D1
    description: "REQUIREMENTS.md's ARTF-07/ARTF-08 bullets and traceability table rows changed from 'Pending' to 'Won't implement — not applicable' with cited D-01..D-08 rationale; ARTF-09/ARTF-10 left unchanged"
    requirement: "ARTF-07"
    verification:
      - kind: other
        ref: "grep -c \"Won't implement\" .planning/workstreams/sgproc-render/REQUIREMENTS.md (returns 4)"
        status: pass
    human_judgment: false
  - id: D2
    description: "ROADMAP.md's Phase 16 phase-list bullet, Goal, and Success Criteria corrected to drop the stale Merkle-tree/content-defined-chunking goal, replaced with a 2-item Success Criteria list plus an explicit 'Won't implement' subsection; Requirements/Depends on/Plans lines unchanged"
    requirement: "ARTF-08"
    verification:
      - kind: other
        ref: "grep -c \"Won't implement\" .planning/workstreams/sgproc-render/ROADMAP.md (returns 6); manual Read confirms exactly 2 numbered Success Criteria and unchanged Requirements line"
        status: pass
    human_judgment: false

duration: 10min
completed: 2026-08-18
status: complete
---

# Phase 16 Plan 1: Correct REQUIREMENTS.md/ROADMAP.md wording for ARTF-07/ARTF-08 Summary

**REQUIREMENTS.md and ROADMAP.md's Phase 16 bookkeeping now shows ARTF-07 (Merkle tree) and ARTF-08 (content-defined chunking) as "Won't implement — not applicable," citing 16-CONTEXT.md D-01..D-08, instead of a stale "Pending"/Merkle-CDC goal.**

## Performance

- **Duration:** 10 min
- **Started:** 2026-08-18T00:16:00Z (approx.)
- **Completed:** 2026-08-18T00:26:47Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- REQUIREMENTS.md's ARTF-07/ARTF-08 bullets and traceability table rows now read "Won't implement — not applicable" with cited D-01..D-04 / D-05..D-08 rationale; checkboxes changed from `- [ ]` to `- [x]`
- ARTF-09/ARTF-10 rows and bullets verified untouched (still "Pending"/`- [ ]`), preserving them for Plans 16-02/16-03 to close
- ROADMAP.md's Phase 16 phase-list bullet, Goal line, and Success Criteria list rewritten to describe only the ARTF-09/ARTF-10 scope this milestone actually implements, with a new "Won't implement (this phase's own conclusion, not a deferral)" subsection replacing the removed Merkle/CDC success criteria
- Both documents now cite the same D-01..D-08 rationale, so a future reader finds consistent, non-contradictory bookkeeping between REQUIREMENTS.md and ROADMAP.md

## Task Commits

Each task was committed atomically:

1. **Task 1: Mark ARTF-07/ARTF-08 as "Won't implement — not applicable" in REQUIREMENTS.md** - `b4ec958` (docs)
2. **Task 2: Correct ROADMAP.md's Phase 16 Goal/Success Criteria to drop the stale Merkle/CDC goal** - `d5993ac` (docs)

**Plan metadata:** (pending — final commit follows this summary)

## Files Created/Modified
- `.planning/workstreams/sgproc-render/REQUIREMENTS.md` - ARTF-07/ARTF-08 bullets and traceability rows marked "Won't implement — not applicable"; ARTF-09/ARTF-10 unchanged
- `.planning/workstreams/sgproc-render/ROADMAP.md` - Phase 16 phase-list bullet, Goal, and Success Criteria corrected; new "Won't implement" subsection added; Requirements/Depends on/Plans lines unchanged

## Decisions Made
- "Won't implement — not applicable" wording used verbatim in both documents (not "deferred"), per 16-CONTEXT.md D-04/D-08's explicit distinction between an architectural conclusion and a resourcing-driven deferral
- Success Criteria renumbered (not kept as "moot" placeholders) — SC1 (Merkle)/SC2 (CDC) removed entirely from the numbered list, consistent with the plan's explicit instruction not to leave stale numbered items
- Coverage/traceability "8 total / 8 mapped / 0 unmapped" counts in REQUIREMENTS.md left untouched — they track phase mapping, not implementation status, and remain literally true

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- REQUIREMENTS.md and ROADMAP.md bookkeeping now accurately reflects Phase 16's actual scope; no further documentation correction needed before Plans 16-02/16-03 execute
- Plans 16-02 (ExecutionManifest::errorMessage + schema-evolution trailer, ARTF-09/ARTF-10) and 16-03 (manifest-on-every-terminal-path, ARTF-09) are unaffected by this plan's edits and remain ready to execute per ROADMAP.md's Wave 1/Wave 2 sequencing

---
*Phase: 16-manifest-evolution*
*Completed: 2026-08-18*

## Self-Check: PASSED

- FOUND: .planning/workstreams/sgproc-render/phases/16-manifest-evolution/16-01-SUMMARY.md
- FOUND: b4ec958 (Task 1 commit)
- FOUND: d5993ac (Task 2 commit)
- FOUND: fa1ae8a (SUMMARY.md commit)
