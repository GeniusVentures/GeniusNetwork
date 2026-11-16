# Phase 13: Bootstrap Branch Merge & Composition Baseline - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-11-16
**Phase:** 13-Bootstrap Branch Merge & Composition Baseline
**Areas discussed:** Merge execution & push posture, Pre-merge baseline & SC2 surface, SC3 verification-gate evidence, Conflict rules & grep gate

---

## Merge execution & push posture

| Option | Description | Selected |
|--------|-------------|----------|
| origin/dev_blockstore | Push the merge to the existing origin branch (same SHA today, fast-forward-style update); one canonical remote line | |
| New origin/dev_coldstorage_additions | Create a new origin branch matching the local name — v1.2 line name canonical on origin; dev_blockstore goes stale | ✓ |
| Decide at push time | Defer destination decision to the push checkpoint itself | |

**User's choice:** New origin/dev_coldstorage_additions
**Notes:** User accepted the stale-dev_blockstore trade-off explicitly.

| Option | Description | Selected |
|--------|-------------|----------|
| Reset pointers, keep untracked | `git submodule update --checkout` to recorded pointers; leave untracked test-data/ alone | |
| Commit drift pre-merge | Commit the pointer moves as explicit pre-merge work | |
| Investigate first | Executor inspects what `89d161b08`/`c6d8c8342` contain vs recorded pointers and reports before reset-vs-keep | ✓ |

**User's choice:** Investigate first
**Notes:** Drift sits exactly on paths the merge itself moves (SGProcessingManager, docs) — disposition is a checkpointed decision, not a default.

| Option | Description | Selected |
|--------|-------------|----------|
| Executor, step-gated | Dry-run (`merge --no-commit`), resolve per checklist, gate each resolution, commit | ✓ |
| User merges manually | Phase becomes verification-only | |
| Executor dry-run, user reviews | Executor pauses for review of every conflict resolution before the merge commit | |

**User's choice:** Executor, step-gated

| Option | Description | Selected |
|--------|-------------|----------|
| Push after all SCs pass | Single evidence-complete push (merge commit + SC4 evidence together) | ✓ |
| Push early, CI proves SC2 | Push right after local pass so origin CI runs the suite on the merged line | |
| Two-stage push | Merge commit early for CI, evidence commit later | |

**User's choice:** Push after all SCs pass

---

## Pre-merge baseline & SC2 surface

| Option | Description | Selected |
|--------|-------------|----------|
| Local pre/post pair | Pre-merge run on 7961ec264 + post-merge on the merge commit, same tree/env (WARP off); CI after push = confirmation, not gate | ✓ |
| Local pair + CI gate | Both surfaces before phase close (exit extends past push) | |
| Reuse v1.1 CI baseline | Tag build 42905264387 numbers as the pre-merge baseline | |

**User's choice:** Local pre/post pair

| Option | Description | Selected |
|--------|-------------|----------|
| Full local, matched scope | Tier-1+2+3, dev-gated included where ran pre-merge; identical scope both sides; explicit exclusions | ✓ |
| Tier-1 + Tier-2 only | Faster; dev-gated excluded | |
| Targeted + Tier-1 | Cold/CRDT/walk-relevant suites + the CI lane | |

**User's choice:** Full local, matched scope

| Option | Description | Selected |
|--------|-------------|----------|
| Evidence file in phase dir | Side-by-side committed table | |
| Fold into SC4 checklist | One artifact for the whole phase | |
| Summary-only, no artifact | Numbers in plan SUMMARY / commit messages only | ✓ |

**User's choice:** Summary-only, no artifact
**Notes:** Deliberately lighter than v1.1 D-05; SC4's checklist+evidence stays committed per its own letter.

| Option | Description | Selected |
|--------|-------------|----------|
| Fresh pre-merge run | Task 1 runs the full suite on clean 7961ec264 before merging | |
| Reuse recent local run | Executor verifies a suitable recent run on 7961ec264 exists, else fresh fallback | ✓ |

**User's choice:** Reuse recent local run

---

## SC3 verification-gate evidence

| Option | Description | Selected |
|--------|-------------|----------|
| New merged-line suite | One new gtest file for all four checks; permanent regression net | |
| Existing suites, cited | Filtered re-runs of existing v1.1 suites + branch's own tests + GATE-03 output, cited per item | ✓ |
| Manual probes | Uncommitted build-tree script; captured output as evidence | |

**User's choice:** Existing suites, cited

| Option | Description | Selected |
|--------|-------------|----------|
| Tier-1 (CI contract) | New tests enforced on every push | |
| Tier-2, local-first | Nothing new in CI this phase | ✓ |

**User's choice:** Tier-2, local-first
**Notes:** Effectively moot given "no new tests" — records the posture.

| Option | Description | Selected |
|--------|-------------|----------|
| Reuse existing check | Re-run v1.1/develop-16 GATE-03 literal-ban; cite pass | ✓ |
| Fold into SC4 gate | One gate script asserting both rules | |

**User's choice:** Reuse existing check

| Option | Description | Selected |
|--------|-------------|----------|
| Deterministic fake-based | InMemoryS3Client + FaultController ordering assert | |
| Log-based observation | Cold-miss scenario; parse fetch order from logs | ✓ |
| Assert + logged demo | Both | |

**User's choice:** Log-based observation
**Notes:** Deterministic enforcement consciously deferred to Phase 15.

---

## Conflict rules & grep gate

| Option | Description | Selected |
|--------|-------------|----------|
| Pre-merge, amended as-run | Predicted hunks + rules before merging; amended with as-run outcomes | ✓ |
| Post-merge as-run only | Checklist written after the merge | |
| Pre-merge only | No amendment; as-run deltas in the merge commit message | |

**User's choice:** Pre-merge, amended as-run

| Option | Description | Selected |
|--------|-------------|----------|
| Compose, escalate collisions | Compose-by-default (cold ours / bootstrap theirs / getNode seam); user checkpoint on true collisions or forecast-exceeding conflicts | ✓ |
| User reviews every hunk | Maximum control, slowest | |
| Executor autonomous | Checkpoint only on locked-decision touches (v1.1 D-15) | |

**User's choice:** Compose, escalate collisions

| Option | Description | Selected |
|--------|-------------|----------|
| Snapshot + symbol identity | Auto-merge snapshot vs committed (hand-edits only in GeniusNode.cpp) + walk-bearing files byte-identical to branch blobs | ✓ |
| Snapshot only | Simpler, slightly weaker | |
| Symbol identity only | Cheapest, misses hand-edits elsewhere | |

**User's choice:** Snapshot + symbol identity

| Option | Description | Selected |
|--------|-------------|----------|
| Workstream phase dir | .planning/workstreams/rocksdb-backup/phases/13-*/ (v1.1 D-05 precedent) | ✓ |
| SuperGenius repo | Travels with code; mixes process evidence into product repo | |
| Split: doc + re-runnable gate | Checklist in workstream; gate script + output in SuperGenius | |

**User's choice:** Workstream phase dir

---

## Todos

| Option | Description | Selected |
|--------|-------------|----------|
| Not related — don't fold | Vulkan capability-probe deadlock todo: keyword-only match (score 0.6), reviewed and kept in backlog | ✓ |
| Fold into Phase 13 | Pull the Vulkan todo into scope | |

**User's choice:** Not related — don't fold

## The Agent's Discretion

Snapshot-capture mechanics, baseline-run suitability criteria, log-parsing approach, investigation report format, checklist granularity, branch-test Windows gating, D-02/D-07 ordering, merge-commit message shape (see CONTEXT.md).

## Deferred Ideas

None — discussion stayed within phase scope (plus one reviewed-not-folded todo above).
