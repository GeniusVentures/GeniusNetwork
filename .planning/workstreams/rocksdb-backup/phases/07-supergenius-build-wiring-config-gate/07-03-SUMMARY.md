---
phase: 07-supergenius-build-wiring-config-gate
plan: 03
subsystem: testing
tags: [tier1, ci, config-gate, flutter, wallet, m3, runbook]

requires:
  - phase: 07-supergenius-build-wiring-config-gate
    provides: ParseColdStorageConfig + ColdStorageEnvLookup contract (plan 07-02)
  - phase: 07-supergenius-build-wiring-config-gate
    provides: verdict=stale CI-readiness decision (plan 07-01)
provides:
  - cold_storage_config_gate_test (15-case hermetic tri-state matrix), Tier1-labeled, registered unconditionally
  - Tier-1 fail-closed CI lane step in cmake.yml (additive; ON-lane blocked-on-release-cut per verdict)
  - GeniusWallet blockstore schema parity (empty-object asset + Settings CRDT whitelist filter)
  - M3 cold-journal ops/runbook section; architecture doc now git-tracked in root
affects: [Phase 8 spill tests, Phase 9 fallback tests, Phase 11 GC/rebuild tooling, wallet Settings]

actuals:
  tokens: 26000
  tasks: 3
  commits: 6

tech-stack:
  added: []
  patterns:
    - "Fail-closed Tier-1 lane transplant to SuperGenius CI (ctest -L Tier1 --no-tests=error, additive to the fail-open full-suite lane)"
    - "Whitelist-filter CRDT table (Network precedent) for nested-config safety"

key-files:
  created:
    - SuperGenius/test/src/crdt/cold_storage_config_gate_test.cpp
    - SuperGenius/.github/workflows/cmake.yml (Tier-1 steps, added)
  modified:
    - SuperGenius/test/src/crdt/CMakeLists.txt
    - SuperGenius/docs/evidence/cold-storage/cold-storage-ci-readiness.md
    - GeniusWallet/assets/crdt_config.json
    - GeniusWallet/lib/settings/settings_screen.dart
    - supergenius-sharded-ipld-cache-architecture.md

key-decisions:
  - "Tier-1 lane registered unconditionally (parse/env code compiles ungated) so -L Tier1 --no-tests=error is non-empty in default OFF builds - the Pitfall 6 gate"
  - "verdict=stale branch taken for the CI ON-lane: blocked-on-thirdparty-release-cut recorded in the readiness doc; local evidence stands in (v1.0 pattern); release cut filed as post-phase follow-up"
  - "Whitelist filter placed at the _buildCrdtSection call site (not in _loadCrdtConfig) so the FULL config (incl. nested blockstore) still round-trips through save untouched"

patterns-established:
  - "SuperGenius-side Tier-1 lane discipline: LABELS at registration + registration-vs-label count gate + fail-closed CI invocation"

requirements-completed: [TEST-01, INTG-02]

coverage:
  - id: D1
    description: "15-case hermetic config-gate matrix, unconditionally registered, Tier-1 lane green and non-empty on the default OFF build"
    requirement: TEST-01
    verification:
      - kind: unit
        ref: "tests: ctest -L Tier1 --no-tests=error on OFF tree -> 100% passed (1 test, 15 cases)"
        status: pass
      - kind: other
        ref: "command: TEST count = 15; addtest(cold_storage count 2 == LABELS Tier1 count 2; registration outside any if(SGNS_COLD_STORAGE)"
        status: pass
    human_judgment: false
  - id: D2
    description: "Tier-1 fail-closed CI step added to both test-running paths; existing fail-open lanes byte-unchanged; ON-lane blocked per stale verdict"
    requirement: TEST-01
    verification:
      - kind: other
        ref: "command: '-L Tier1 --no-tests=error' matches = 2; -LE requires_foundry count unchanged (4); diff = 20 insertions, 0 deletions; readiness doc carries blocked-on-release-cut section"
        status: pass
    human_judgment: false
  - id: D3
    description: "GeniusWallet schema parity: blockstore empty-object asset (backup keys verbatim) + CRDT editor whitelist filter"
    requirement: INTG-02
    verification:
      - kind: other
        ref: "command: asset parses with blockstore object + 4 backup keys intact; keyLabels.containsKey filter present; flutter analyze - no issues in settings_screen.dart (1 pre-existing unrelated warning)"
        status: pass
    human_judgment: false
  - id: D4
    description: "M3 cold-journal runbook documented (rebuildable-not-backed-up, recovery sequence, Phase-11 tooling, env credentials); doc git-tracked"
    requirement: INTG-02
    verification:
      - kind: other
        ref: "command: 'rebuildable' + SGNS_BLOCKSTORE_S3_ACCESS_KEY anchors present; git ls-files shows the doc tracked"
        status: pass
    human_judgment: false

duration: 50 min
completed: 2026-10-23
status: complete
---

# Phase 7 Plan 03: TEST-01 Anchor + INTG-02 Evidence Summary

**Hermetic 15-case config-gate matrix green in a fail-closed Tier-1 lane (non-empty on OFF builds), additive CI lane step committed (ON-lane blocked-on-release-cut per verdict=stale), wallet schema parity shipped with the Pitfall-7 corruption fix, and the M3 cold-journal posture documented and tracked.**

## Performance

- **Duration:** ~50 min | **Tasks:** 3 | **Files:** 5 modified + 1 created (test TU)

## Accomplishments
- `cold_storage_config_gate_test`: all 15 named matrix cases pass; Tier-1 lane on the default OFF tree: `100% tests passed, 0 failed out of 1` — fail-closed and non-vacuous
- CI: `Tier-1 fail-closed lane` steps added after both `Run tests` paths (Windows/macOS + Linux); existing `-LE requires_foundry` invocations byte-unchanged; 20-insertion/0-deletion diff
- ON-lane: `verdict=stale` branch honored — no failing CI job wired; `blocked-on-thirdparty-release-cut` recorded with the re-verification command and post-phase release-cut follow-up
- Wallet: `blockstore: {}` asset parity (4 backup keys verbatim, parses as valid JSON); Settings CRDT table filtered by the `crdtKeyLabels` whitelist so nested entries round-trip untouched
- Architecture doc: M3 ops/runbook section (D-09/D-10) with recovery sequence + `SGNS_BLOCKSTORE_S3_*` guidance; file first-tracked in root

## Task Commits

1. **Task 1: matrix + registration** — SuperGenius `2703a75fe`, root `b8e0a62` (test)
2. **Task 2: CI lane + stale-verdict record** — docs `b677d61`, SuperGenius `f4e9ee31c`, root `f6a71e8` (feat/docs)
3. **Task 3: wallet parity + M3 runbook** — GeniusWallet `6b5c475b`, root `3e86946` (feat/docs)

**Plan metadata:** this commit (docs)

## Decisions Made
- Unconditional registration (Pitfall 6) + whitelist at the call site (full-map round-trip preserved)
- Comment wording adjusted twice so the count-based gates (LABELS/Tier1, -LE requires_foundry) read clean — gate hygiene over comment literalism

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Plan-verify mismatch] `-LE requires_foundry` count expectation**
- **Found during:** Task 2 verify
- **Issue:** plan expects grep count 2; the file has 4 matching lines pre-edit (3 invocation lines + 1 comment line at :600). The "2" matches neither lines nor steps
- **Fix:** used the invariant form — count unchanged before/after (4) + additions-only diff (20+/0-) + both new comments reworded to not embed the literal string
- **Verification:** count 4 before and after; diff clean

**2. [Rule 1 - Gate hygiene] 07-01 comment embedded the literal `LABELS "Tier1"`**
- **Found during:** Task 1 verify
- **Issue:** registration-vs-label count read 2==3 because a comment in the link_proof block contains the literal
- **Fix:** reworded the comment; count now 2==2
- **Commit:** f4e9ee31c

**3. [Observation - recorded, not skipped] flutter analyze toolchain gap**
- One pre-existing warning (`include_file_not_found` for `package:lints/recommended.yaml` in `packages/genius_api/analysis_options.yaml`); zero issues in `settings_screen.dart`; no error-level findings. Recorded per the plan's instruction not to silently skip

**Total deviations:** 2 auto-fixed + 1 recorded observation. **Impact:** none.

## Self-Check: PASSED

- Task 1: lane green + non-empty on OFF tree; 15 TEST cases; 2==2; unconditional registration ✓
- Task 2: 2 Tier-1 steps; -LE count unchanged; additions-only; stale-verdict block committed ✓
- Task 3: asset valid + intact; whitelist present; doc anchors present + tracked ✓
- Plan-level verification: all local proofs green; CI runtime proof deferred to user push (user_setup), flagged not assumed
