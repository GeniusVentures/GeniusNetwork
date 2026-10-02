---
phase: 05-ci-integration
plan: 01
subsystem: infra
tags: [github-actions, ci, path-filter, worker-tests, node22, cloudflare-worker]

requires:
  - phase: 01-token-gnus-ai-worker-service
    provides: hermetic pricecoordinator vitest suite + package.json scripts (typecheck/test) + committed lockfile
provides:
  - Path-gated `worker-tests` CI job (Node 22, npm ci -> typecheck -> vitest run) in SuperGenius/.github/workflows/cmake.yml, separate from the C++ matrix
affects: [Phase 5 CI (05-02), future pricecoordinator changes]

tech-stack:
  added: [dorny/paths-filter@v3 (GitHub Action), actions/setup-node@v4]
  patterns:
    - "Non-matrix sidecar test job gated by dorny/paths-filter with workflow_dispatch bypass; steps (not triggers) carry the gate"

key-files:
  created: []
  modified:
    - SuperGenius/.github/workflows/cmake.yml

key-decisions:
  - "Gate lives on the job steps (setup-node + 3 npm steps), not the workflow trigger - preserves the .github/** paths-ignore policy exactly (D-01, D-02)"
  - "dorny/paths-filter base = github.event.before for pushes, PR API otherwise; workflow_dispatch skips the filter and is treated as an explicit run request"
  - "Job-scoped read-only permissions (contents: read, pull-requests: read) with token-limited filter - no package-write or deployment grants (T-05-01/02)"

patterns-established:
  - "Sidecar hermetic-test job pattern: cheap non-matrix job + path filter + dispatch bypass, alongside an unchanged heavyweight build matrix"

requirements-completed: [TEST-06]

coverage:
  - id: D1
    description: "worker-tests job runs Node 22 + npm ci + typecheck + vitest for Worker-directory changes"
    requirement: TEST-06
    verification:
      - kind: source
        ref: "Assertions: exactly one '  worker-tests:' job; node-version: 22; cache-dependency-path pricecoordinator/package-lock.json; working-directory: pricecoordinator; all three npm commands present"
        status: pass
      - kind: command
        ref: "Local: npm ci OK, npm run typecheck OK, npm run test OK (10 files, 63 tests, 8.04s)"
        status: pass
  - id: D2
    description: "C++-only changes do not run setup-node or npm"
    requirement: TEST-06
    verification:
      - kind: source
        ref: "Every Node/npm step carries if: github.event_name == 'workflow_dispatch' || steps.changes.outputs.worker == 'true'; filter matches only pricecoordinator/**"
        status: pass
      - kind: manual-pending
        ref: "Positive/negative path-gate evidence from real push/PR runs deliberately deferred to 05-02's dispatched verification (D-01 makes a pre-merge C++-only event unavailable); noted in Deviations"
        status: pending
  - id: D3
    description: "Trigger policy, C++ matrix, and CTest invocation unchanged"
    requirement: TEST-06
    verification:
      - kind: source
        ref: "paths-ignore count == 2 with .github/** in both push and pull_request; ctest . -j invocations byte-identical; diff is +52 lines append-only"
        status: pass

key-caveats:
  - "Live push/PR proof of both gate outcomes is pending by design: a workflow-only edit cannot trigger the workflow itself (D-01). The manual-verification criterion stays open until the first real event after this lands on a base branch; workflow_dispatch proves only the positive path."

duration: 9min
completed: 2026-10-02
---

# Phase 5 Plan 01: worker-tests CI Job Summary

**Path-gated Node 22 `worker-tests` job (npm ci -> typecheck -> vitest) added to Release Build CI as a non-matrix sidecar, with the existing trigger policy and C++ matrix untouched.**

## Performance

- **Duration:** 9 min
- **Started:** 2026-10-02T14:26:47Z
- **Completed:** 2026-10-02T14:35:40Z
- **Tasks:** 2
- **Files modified:** 1 (`SuperGenius/.github/workflows/cmake.yml`, +52 lines)

## Accomplishments

- `worker-tests` job on `ubuntu-latest`: checkout (v7, repo-root) -> `dorny/paths-filter@v3` (id `changes`, `worker: pricecoordinator/**`) -> conditional `setup-node@v4` (Node 22, npm cache keyed by `pricecoordinator/package-lock.json`) -> conditional `npm ci` / `npm run typecheck` / `npm run test` with `defaults.run.working-directory: pricecoordinator`
- C++-only changes never initialize Node: every Node/npm step is gated on `workflow_dispatch` OR `steps.changes.outputs.worker == 'true'`; `workflow_dispatch` runs the Worker checks unconditionally as the explicit-run path
- Job runs with least privilege (`contents: read`, `pull-requests: read`); the paths-filter uses only the job's read-only `github.token`
- Workflow trigger policy byte-identical: `paths-ignore` (incl. `.github/**`) unchanged in both `push` and `pull_request`; C++ matrix, CTest steps, and caches untouched

## Task Commits

1. **Tasks 1+2: Worker-directory change gate + locked Node 22 checks** - `7b34a4440` in `GeniusVentures/SuperGenius` (feat) - `dev_tokenprice`

**Plan metadata:** parent-repo pointer bump + this summary (see below).

## Files Created/Modified

- `SuperGenius/.github/workflows/cmake.yml` - new `worker-tests` job (+52 lines, append-only after the CTest cost-data save step)

## Verification Evidence

- Plan assertions (single-quoted heredoc): `worker-tests:` count == 1, `paths-ignore:` count == 2, `.github/**` count == 2, `pricecoordinator/**` present, no `SuperGenius/pricecoordinator/**` prefix, `pull-requests: read` present, Node 22 / cache path / working-directory / all three npm commands / dispatch gate / filter-output gate / `ctest . -j` intact - all PASS
- YAML parse: `yaml.safe_load` OK; jobs `[resolve-runners, build, worker-tests]`; step names and defaults verified
- Local toolchain run from `SuperGenius/pricecoordinator`: `npm ci` OK (audit warnings pre-existing, lockfile audited per 01-RESEARCH.md) -> `npm run typecheck` OK (both tsconfigs) -> `npm run test` OK: **10 test files / 63 tests passed** in 8.04s (miniflare `deleteAllDurableObjects` stderr lines are known noise from the DO-eviction tests, not failures)
- `git diff --check` clean; `actionlint` not installed locally - YAML parse + GitHub Actions schema knowledge used instead

## Decisions Made

- Comment wording in the job avoids a literal `.github/**` token so the plan's exact-count source assertion (2 = the two paths-ignore entries) holds
- `token: ${{ github.token }}` passed to paths-filter explicitly (rather than omitting) to pin the action to the job's restricted permission set (T-05-01/02)

## Deviations from Plan

### Deferred verification (not auto-fixed)

**1. Manual path-gate evidence from real push/PR events**
- **Found during:** Task 1 verify (manual criteria)
- **Issue:** Plan's manual verification requires inspecting a Worker-path change run (`worker=true`, steps execute) and a C++-only change run (`worker=false`, steps skipped). Because `.github/**` is paths-ignored (D-01), this workflow-only edit cannot trigger the workflow, and the branch is not yet on a base branch for other events to exercise the gate
- **Disposition:** Deferred, per the plan's own guidance ("leave this criterion pending until such a run supplies evidence"). Static gate conditions + local toolchain run committed now; live-event proof rides the same verification window as 05-02's dispatched aarch64-Debug run
- **Impact on plan:** None on delivered artifacts; verification debt explicitly tracked in key-caveats

**Total deviations:** 0 auto-fixed, 1 verification deferred by plan design.

## Issues Encountered

- First python inline assertion attempt failed on PowerShell quote-stripping (`python -c` with nested quotes) - resolved by piping a here-string to stdin; also caught and reworded a job comment that inflated the `.github/**` literal count past the plan's assertion

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- 05-02 (aarch64-Debug exclusion removal) can proceed; both edits share `cmake.yml` and land on the same branch, then one `workflow_dispatch` verification run covers the Linux-aarch64_Debug leg (and, per dispatch semantics, exercises the new worker-tests job's positive path)

---
*Phase: 05-ci-integration*
*Completed: 2026-10-02*
