# 13-01 SUMMARY — Merge Pre-conditions & Zero-Regression Denominator (RECOVER-01)

**Phase:** 13 Bootstrap Branch Merge & Composition Baseline · **Plan:** 13-01 · **Wave:** 1
**Status:** COMPLETE · **Date:** 2026-11-16

## What Was Built

1. **D-02 dirty-tree disposition (Task 1)** — drift evidence re-verified live (both nested-submodule dirty values `89d161b08`/`c6d8c8342` are merge-base values AND ancestors of the recorded pointers `dc8a994cb`/`77f4fcfd5`; `git ls-files test-data/` empty; no merge command had run). Blocking checkpoint presented with the full table; user picked **reset** with the qualification "procmanager should be at dc8a994cb… to work with our moltenvk setup" (recorded verbatim). `git submodule update SGProcessingManager docs` executed; pointer equality verified; post-disposition verify `reset-clean-ok`.
2. **D-13 predicted merge checklist (Task 2)** — `13-MERGE-CHECKLIST.md` committed (root `4eb9836`), Status **PREDICTED**: topology table, the verbatim single `ShutdownForDestruction` conflict, the mechanical per-hunk compose rule, both-side hunk maps (8 ours / 12 theirs, base-2530 the only overlap), the exact D-15a/D-15b gate commands, the SC3 four-row skeleton, as-run sections, and the D-04 push section. All 9 required markers + all 6 named test cases verified present.
3. **SC2 pre-merge baseline (Task 3)** — full suite on binaries freshly rebuilt at `7961ec264` (incremental, exit 0, 5m44s; HEAD verified pre-build): **167 total / 166 passed / 1 failed**. Sole failure root-caused (see Deviation 1) and fixed on the baseline at `4ae8a9a4e`; fixed suite + Tier-1 lane re-verified green at the tip. WARP adapter ABSENT. Denominator = user-approved composed baseline (see Deviation 2).

## Files Modified

- `.planning/workstreams/rocksdb-backup/phases/13-bootstrap-branch-merge-composition-baseline/13-MERGE-CHECKLIST.md` (created, then amended §1/§7.3 for the new ours-tip + composed-baseline record)
- `SuperGenius/test/src/crdt/cold_storage_resurrection_test.cpp` (one case rewritten to the keep-seal retention contract)
- `SuperGenius/.git/config` (local-only, uncommitted: `submodule.SGProcessingManager.ignore untracked` — scratch carve-out, see Deviation 3)
- `13-02-PLAN.md` / `13-04-PLAN.md` (pinned ours-tip amended `7961ec264` → `4ae8a9a4e` per user-approved disposition b)

## Commits

| Repo | SHA | Message |
|------|-----|---------|
| root | `f983ad7` | docs(13): renumber cross-plan duplicate threat IDs to T-13-07..T-13-10 (threat-id gate #4683, RECOVER-01) — orchestration pre-gate |
| root | `4eb9836` | docs(13-01): author predicted D-13 merge checklist (RECOVER-01 pre-merge) |
| SuperGenius | `4ae8a9a4e` | test(13-01): align trimmed-marker resurrection case with keep-seal retention |
| root | (this commit) | docs(13-01): write summary; amend plans for fixed baseline tip 4ae8a9a4e |

## SC2 Pre-Leg Numbers (D-08: recorded here, not in a committed baseline artifact)

- Full suite @ `7961ec264` (freshly rebuilt binaries): **167 total, 166 passed, 1 failed** — `cold_storage_resurrection_test` (16.98s in-suite; deterministic isolated re-run, same case)
- Failed-test name list (the comparison set for 13-03): `cold_storage_resurrection_test` — root-caused + fixed at `4ae8a9a4e` (see Deviation 1); post-leg subset gate therefore compares against a single-entry denominator whose entry is fixed on the merge line
- Composed denominator @ `4ae8a9a4e`: 166 carried results (byte-identical binaries — the fix commit touched one test file only) + resurrection suite green (all cases) + **Tier-1 lane 12/12, `--no-tests=error` exit 0** (104.98s)
- `requires_foundry` family: 9 tests, **all PASSED locally** — the anticipated shared exclusion set is EMPTY (develop's 150/151 precedent did not reproduce here)
- WARP adapter: ABSENT (per-leg check recorded)
- Wall-clock: full suite **33m34s** serial (ctest total 2014.41s — Phase 19 planning input); incremental rebuild 5m44s @ `7961ec264`, 5s no-op @ `4ae8a9a4e`

## Deviations from Plan

1. **[Rule 1 — bug in existing test; user-ruled fix-first] Stale resurrection evidence-wait on the pre-leg.** Found during: Task 3. Issue: `Resurrect_TrimmedMarker_TombstoneDominanceKeepsValueAbsent` failed deterministically on exactly `7961ec264` — its 10s poll waits for a post-trim S3 re-fetch, but the keep-seal commit (`7961ec264` itself) makes the retained seal marker the walk terminator (the commit message's stated purpose: prevent re-fetch storms), so the fetch never fires. Timeline verified with the user: last CI green `9994718ce` (Nov 10, run 42905264387); both behavior-changing commits (`55fca03f8` develop-merge + `7961ec264` keep-seal) landed Nov 12 and NO CI run exists at/after them; the suite was never executed under the new semantics until this pre-leg (exactly the D-07 gap the fresh run was mandated to close). Fix: case rewritten to the retention contract, mirroring the marker-present sibling (zero S3 Gets across the re-delivery storm, no re-journal, value stays absent) — SuperGenius `4ae8a9a4e`. Verification: full resurrection suite green + Tier-1 12/12 at the new tip.
2. **[User-approved deviation from plan letter] Composed pre-leg denominator instead of a fresh full-suite re-run at `4ae8a9a4e`.** The user ruled the ~33-min re-run unnecessary after the one-test fix ("we just needed to fix one test"). Substance: the fix commit changed one test file; the other 166 test binaries are byte-identical, so their pass results carry; the changed target + Tier-1 lane were re-verified green at the tip. The plan's Tier-1-exit-0 criterion is satisfied at the baseline tip `4ae8a9a4e` (it had exited 8 at `7961ec264` on the since-fixed test only). Impact: none on the 13-03 subset gate (single-entry pre-failure list, that entry fixed on the merge line).
3. **[Rule 2 — verify gap in plan] D-02 drift check did not carve out nested untracked scratch.** The post-disposition verify flagged ` M SGProcessingManager (untracked content)` after a successful pointer re-sync — the propagated untracked `test/fixtures/` scratch inside the nested repo (explicitly ignorable per D-02, "scratch left in place unless user says otherwise"), not pointer drift. Fix: local uncommitted `git config submodule.SGProcessingManager.ignore untracked` (scoped — tracked modifications still surface); substance verified by `ls-tree HEAD` == nested `rev-parse HEAD`. User scratch preserved.
4. **[User-approved consequence of disposition b] Ours-tip pin moved `7961ec264` → `4ae8a9a4e`.** 13-02's parent/merge-tree pins and 13-04's evidence presentation amended accordingly; the research reference merge-tree OID is now expected to DIFFER (same conflict file-set, different tree bytes). Recorded in checklist §1.
5. **[Orchestration pre-gate] Threat-ID duplicates T-13-01/03/04 renumbered** to T-13-07..T-13-10 per the #4683 hard stop (root `f983ad7`) — no plan content changed beyond the register rows.

**Total deviations:** 5 (1 auto-fixed, 4 user-approved/orchestration). **Impact:** merge legality unchanged; denominator is green at the baseline tip with full attribution; 13-02 now pins the fixed tip.

## Verification Results

- D-02: `reset-clean-ok` (conditioned automated verify, pick recorded verbatim at `%TEMP%\p13-d02-pick.txt`)
- Checklist markers: `all-9-markers-present`, `all-6-case-names-present`, committed in latest root commit at check time
- Pre-leg provenance: HEAD `7961ec264` verified → rebuild exit 0 → full-suite log summary parsed; Tier-1 at `4ae8a9a4e`: exit 0, 12/12
- No merge command, no push, no submodule pointer commit ran in this plan (D-02/D-04 discipline held)

## Self-Check: PASSED
