---
phase: 11-empirical-cross-machine-capture-run
plan: 01
subsystem: infra
tags: [docs, capture-harness, vulkan, mnn, quantization, cross-hardware]

# Dependency graph
requires:
  - phase: 10-capture-harness-diff-tool-quantization-stub
    provides: capture_harness/capture_diff CLI tools and the .cap/diff-JSON output formats consumed here
provides:
  - Phase-owned captures/ directory (4 .cap files + 2 diff JSONs, Mac + Windows only)
  - 11-CAPTURE-RESULTS.md citing exact cross-machine divergence numbers
  - ROADMAP.md/REQUIREMENTS.md wording reconciled to the accepted 2-machine scope
  - STATE.md Operator Next Steps/Pending Todos reconciled to D-01/D-02
affects: [12-quantization-normalization-implementation, 13-re-validation-scope-boundary-documentation]

# Tech tracking
tech-stack:
  added: []
  patterns: []

key-files:
  created:
    - .planning/workstreams/sgproc-render/phases/11-empirical-cross-machine-capture-run/captures/diff-mnn-float.json
    - .planning/workstreams/sgproc-render/phases/11-empirical-cross-machine-capture-run/captures/diff-render.json
    - .planning/workstreams/sgproc-render/phases/11-empirical-cross-machine-capture-run/captures/xhw-mnn-float_Fuus-Mac-mini.local---macOS_20260811T212907.cap
    - .planning/workstreams/sgproc-render/phases/11-empirical-cross-machine-capture-run/captures/xhw-mnn-float_Mofu---Windows_20260811T212812.cap
    - .planning/workstreams/sgproc-render/phases/11-empirical-cross-machine-capture-run/captures/xhw-render_Fuus-Mac-mini.local---macOS_20260811T213105.cap
    - .planning/workstreams/sgproc-render/phases/11-empirical-cross-machine-capture-run/captures/xhw-render_Mofu---Windows_20260811T213052.cap
    - .planning/workstreams/sgproc-render/phases/11-empirical-cross-machine-capture-run/11-CAPTURE-RESULTS.md
  modified:
    - .planning/workstreams/sgproc-render/ROADMAP.md
    - .planning/workstreams/sgproc-render/REQUIREMENTS.md
    - .planning/workstreams/sgproc-render/STATE.md

key-decisions:
  - "Repo-root caps/ (untracked) relocated via plain filesystem move into phase-owned captures/; WSL/llvmpipe MNN-float capture dropped and deleted per D-04/D-09"
  - "ROADMAP.md Phase 11 SC1 and Goal line, plus REQUIREMENTS.md QUANT-04 and its Phase 11 traceability note, all reworded from '3 machines' to '2 machines (Mac + Windows)' with a software-rasterizer-exclusion caveat, per D-03"
  - "ROADMAP.md's Phase 11 phase-list summary bullet ('Mac + PC + a third') left untouched -- the plan named only SC1 and the Phase Details Goal line as in-scope discretionary edits"
  - "STATE.md's stale 'get the third machine's .cap files' Operator Next Steps instruction and 'formally kick off discuss-phase' Pending Todos line replaced verbatim per D-01/D-02"

patterns-established: []

requirements-completed: []

coverage:
  - id: D1
    description: "captures/ contains exactly the 4 Mac/Windows .cap files + 2 diff JSONs (6 files total), relocated from repo-root caps/ which no longer exists; WSL/llvmpipe capture excluded"
    verification:
      - kind: other
        ref: "shell verification: test -d captures && 6 files present && diff-mnn-float.json/diff-render.json present && caps/ removed -- see plan Task 1 <verify> block, ran and passed (echo OK)"
        status: pass
    human_judgment: false
  - id: D2
    description: "11-CAPTURE-RESULTS.md cites exact maxAbsDelta/maxRelDelta/maxUlpDistance/percentExceedingThreshold and per-hash-type booleans from both diff JSONs, states D-01 (2-machine scope) and D-04 (dropped WSL) as required sections, and identifies both machines by exact .cap-filename labels"
    verification:
      - kind: other
        ref: "shell verification: grep -q for each exact numeric/boolean/label token in 11-CAPTURE-RESULTS.md -- see plan Task 2 <verify> block, ran and passed (echo OK)"
        status: pass
    human_judgment: false
  - id: D3
    description: "ROADMAP.md Phase 11 SC1 and REQUIREMENTS.md QUANT-04 reworded to 2-machine scope with software-rasterizer caveat; Phase 12/13 and VALD-01 wording left untouched; STATE.md Operator Next Steps/Pending Todos no longer instruct gathering a third machine's captures"
    verification:
      - kind: other
        ref: "shell verification: grep -q for target phrasing in ROADMAP.md/REQUIREMENTS.md/STATE.md plus grep -q absence checks for stale phrasing -- see plan Task 3 <verify> block, ran and passed (echo OK); manually confirmed Phase 12 SC, Phase 13 Goal/SC, and REQUIREMENTS.md VALD-01 unchanged via grep"
        status: pass
    human_judgment: false

duration: 5min
completed: 2026-08-12
status: complete
---

# Phase 11 Plan 01: Empirical Cross-Machine Capture Run Summary

**Formalized this session's ad-hoc Mac+Windows capture run as Phase 11's deliverable: relocated 6 evidence files into a phase-owned `captures/` directory, wrote `11-CAPTURE-RESULTS.md` citing the exact diff-JSON numbers (maxAbsDelta ≈1.043e-07, maxRelDelta ≈7.27e-05, maxUlpDistance 768 for MNN-float; contentHashMatch true / combinedHashMatch false for render), and reconciled ROADMAP.md/REQUIREMENTS.md/STATE.md's stale "3-machine" wording to the accepted 2-machine scope.**

## Performance

- **Duration:** 5 min
- **Started:** 2026-08-12T00:03:12Z
- **Completed:** 2026-08-12T00:08:39Z
- **Tasks:** 3 completed
- **Files modified:** 10 (6 created under `captures/`, 1 new results doc, 3 edited docs)

## Accomplishments
- Relocated the 4 Mac/Windows `.cap` files + 2 `capture_diff` JSON reports from untracked repo-root `caps/` into this phase's `captures/` directory, dropping the WSL/llvmpipe MNN-float capture per D-04 and deleting the now-empty `caps/` directory
- Wrote `11-CAPTURE-RESULTS.md`, embedding both diff JSONs verbatim and citing their exact numeric/boolean fields, with required "Scope Decision" (D-01) and "Dropped WSL/MNN Capture" (D-04) sections plus an "Implications for Phase 12" close
- Reconciled ROADMAP.md's Phase 11 Success Criterion 1 and Goal line, and REQUIREMENTS.md's QUANT-04 and Phase 11 traceability note, from "≥3 machines" to "≥2 machines (Mac + Windows)" with a software-rasterizer-exclusion caveat, per D-03 — leaving Phase 12/13's own "3-machine" wording and REQUIREMENTS.md's VALD-01 untouched
- Corrected STATE.md's stale "get the third machine's .cap files ... before Phase 11 can close out" Operator Next Steps instruction and the "formally kick off discuss-phase" Pending Todos line, both superseded by D-01/D-02

## Task Commits

Each task was committed atomically:

1. **Task 1: Relocate capture evidence into the phase-owned captures/ directory** - `187f863` (docs)
2. **Task 2: Write 11-CAPTURE-RESULTS.md citing both diff JSONs' exact numbers** - `a8054c3` (docs)
3. **Task 3: Reconcile ROADMAP.md, REQUIREMENTS.md, and STATE.md wording to the 2-machine scope** - `150f7dc` (docs)

**Plan metadata:** pending (docs: complete plan, this commit)

## Files Created/Modified
- `.planning/workstreams/sgproc-render/phases/11-empirical-cross-machine-capture-run/captures/diff-mnn-float.json` - relocated Mac-vs-Windows MNN-float diff report
- `.planning/workstreams/sgproc-render/phases/11-empirical-cross-machine-capture-run/captures/diff-render.json` - relocated Mac-vs-Windows render diff report
- `.planning/workstreams/sgproc-render/phases/11-empirical-cross-machine-capture-run/captures/xhw-mnn-float_Fuus-Mac-mini.local---macOS_20260811T212907.cap` - relocated Mac MNN-float capture
- `.planning/workstreams/sgproc-render/phases/11-empirical-cross-machine-capture-run/captures/xhw-mnn-float_Mofu---Windows_20260811T212812.cap` - relocated Windows MNN-float capture
- `.planning/workstreams/sgproc-render/phases/11-empirical-cross-machine-capture-run/captures/xhw-render_Fuus-Mac-mini.local---macOS_20260811T213105.cap` - relocated Mac render capture
- `.planning/workstreams/sgproc-render/phases/11-empirical-cross-machine-capture-run/captures/xhw-render_Mofu---Windows_20260811T213052.cap` - relocated Windows render capture
- `.planning/workstreams/sgproc-render/phases/11-empirical-cross-machine-capture-run/11-CAPTURE-RESULTS.md` - new results doc citing exact diff numbers, D-01/D-04 sections, Phase 12 implications
- `.planning/workstreams/sgproc-render/ROADMAP.md` - Phase 11 SC1 + Goal line reworded to 2-machine scope
- `.planning/workstreams/sgproc-render/REQUIREMENTS.md` - QUANT-04 + Phase 11 traceability note reworded to 2-machine scope
- `.planning/workstreams/sgproc-render/STATE.md` - Operator Next Steps + Pending Todos reconciled to D-01/D-02

## Decisions Made
- Deleted the dropped WSL/llvmpipe MNN-float capture outright (rather than archiving it untracked) per D-09's explicit executor discretion, since repo-root `caps/` was being removed in the same task and nothing downstream needs it
- Left ROADMAP.md's Phase 11 phase-list summary bullet ("Mac + PC + a third") untouched — the plan's action text named only Success Criterion 1 and the Phase Details Goal line as in-scope discretionary consistency edits for ROADMAP.md; this line is a small residual inconsistency documented here rather than silently fixed outside the plan's stated scope

## Deviations from Plan

None - plan executed exactly as written. No auto-fixes were needed; this was a pure documentation/data-organization phase with no source code touched.

## Issues Encountered

None. `caps/` at repo root was entirely untracked by git (not just its contents), so the relocation was a plain filesystem move/delete with no `git mv`/`git rm` step needed for the source side — confirmed via `git status` before and after.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Phase 11 is complete: the 2-machine empirical dataset (Mac + Windows, both fixtures) lives in `captures/`, `11-CAPTURE-RESULTS.md` gives Phase 12's normalization design concrete numbers to cite (maxAbsDelta ≈1.043e-07, maxRelDelta ≈7.27e-05, maxUlpDistance 768 for MNN-float; the render fixture's `contentHashMatch: true` / `combinedHashMatch: false` nuance flagged for Phase 12's attention), and ROADMAP.md/REQUIREMENTS.md/STATE.md no longer contradict the accepted 2-machine scope. No blockers for Phase 12 (Quantization/Normalization Implementation).

---
*Phase: 11-empirical-cross-machine-capture-run*
*Completed: 2026-08-12*

## Self-Check: PASSED

All 6 relocated `captures/` files, `11-CAPTURE-RESULTS.md`, and this SUMMARY.md confirmed present on disk via `test -f`. Repo-root `caps/` confirmed removed via `[ ! -d caps ]`. All 3 task commit hashes (`187f863`, `a8054c3`, `150f7dc`) confirmed present via `git log --oneline --all`.
