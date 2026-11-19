---
phase: 17-seal-growth-measurement-decision
plan: 03
subsystem: crdt/cold-storage (documentation + conditional production touch)
tags: [seal-growth, decision-record, d-12-verdict, d-11-triggers, walk-bounds]
key-files:
  created:
    - .planning/workstreams/rocksdb-backup/notes/17-seal-growth-decision.md
  modified:
    - .planning/workstreams/rocksdb-backup/STATE.md
metrics:
  d12_band: "±25% (max of 16.152% measured CV and 25% recorded slack)"
  d12_verdict: "validated, in-band-with-noted-limitation"
  production_touch: "none (in-band branch — zero SuperGenius/src diff vs 741980f5d)"
  d11_triggers: "T1 bytes band [46,60]; T2 10s at 10^7; T3 20GB at 10^8"
---

# Plan 17-03 Summary: D-12 Band + SC2 Verdict + SC3 Decision Record

## What Was Done

**Task 1 — band, verdict, (skipped) re-tune, with the chronology proof:**
- **Band committed first** (`de04874`): ±25% — the larger of the measured repeat variance (max CV 16.152% at the 10⁷ warm point, `leg.volume_10e7.enum_warm.cv_pct`) and a 25% absolute slack (rationale recorded: day-to-day spread + the 22.8% in-run first-pass outlier). The comparison metric definition embeds the **symmetric reduced-observability clause** as the plan requires.
- **Verdict committed second** (`20656e9`): **VALIDATED — in-band, with noted limitation.** Inputs: `leg.fidelity.walk.*` (Completed, visited 64, skipped_existing 64, **walk_gaps 0**, errors 0), topology `leg.fidelity.topology` (hermetic datastore-level + W3 alias), attempts-per-CID unobservable (fetched = restored = 0). Bound-binding disjunct: not triggered (zero gaps). Dead-weight disjunct: the topology exercised zero peer-failover attempts → the symmetric clause engages → below-envelope reading is a topology artifact → recorded as **in-band-with-noted-limitation**, never dead-weight evidence. The limitation (bound tightness unobservable hermetically; non-interference proven) is named in the doc.
- **IN-BAND branch executed:** NO production edit — `kForcedWalkPeerFailoverPerCid` stays **8**, and `git -C SuperGenius diff --name-only 741980f5d -- src` is **empty** (the branch's evidence). Tier-1 lane green at close.

**Task 2 — the completed SC3 decision record + STATE one-liner** (`3b7739f`):
- `notes/17-seal-growth-decision.md` in the 16-rulings shape: (a) the growth anatomy (52.000 B/row measured at every scale; shared-CF mix 8/211; density spectrum on record); (b) the **ACCEPT** ruling with D-13 spectrum-band capacity math (10⁶/10⁷ measured, 10⁸ extrapolated-and-labeled, every figure citing a JSON key); (c) the band derivation; (d) the verdict with observability posture; the **options table** (accept | spill | compaction | sidecar — the latter three rejected/deferred citing REQUIREMENTS Future and invariant 3); **D-11 numeric triggers** T1–T3 (each with threshold, JSON key, derivation note); Evidence; D-08 re-run instructions linking the evidence README; the **four-source citation list** (in-code derivation comment, the two sibling 8-bounds, develop-line 19-07-SUMMARY, this phase's probe JSON); forward pointers to Phase 18/19 and any future redesign milestone.
- **STATE.md**: exactly one new key-decisions bullet (outcome + doc path + evidence path + D-12 verdict); Current Position untouched.

## Commits

| Task | Commit | Description |
|---|---|---|
| 1 | `de04874` | docs(17): D-12 band derived from committed variance (SEAL-01 SC2) |
| 1 | `20656e9` | docs(17): SC2 walk-bounds verdict recorded (validated, in-band-with-noted-limitation) |
| 2 | `3b7739f` | docs(17): seal-growth decision record + D-11 triggers + STATE one-liner (D-10/D-11/D-13, SEAL-01 SC3) |

Chronology proof: the doc carries 3 commits in the required order (band → verdict → completion); no constant amendment follows (in-band).

## Verification Evidence

- All Task 1 + Task 2 gates green: band/verdict mentions 17 ≥ 4; observability mentions 2 ≥ 2; verdict line present; constant = 8; production diff EMPTY; doc commits 3 ≥ 2; sections 11 ≥ 6; ruled-out phrase `v1.1 recovery-suite` ABSENT; JSON-key citations 23 ≥ 5; STATE one-liner present; zero tracked SuperGenius modifications (the one untracked path is pre-existing-suite runtime fixtures, `cold-read-freeze`).
- Tier-1 lane: **17/17 green**.

## Deviations from Plan

None — the plan executed exactly as written; the in-band branch was selected by the committed numbers (walk_gaps = 0; hermetic topology observability), not by choice.

## Self-Check: PASSED

- All tasks executed and committed; SUMMARY created; tracking updated by the orchestrator close-out.
- Acceptance criteria re-verified: chronology via git history; verdict names inputs/band/result/observability posture; in-band → zero SuperGenius/src diff; derivation comment untouched (no edit at all); lane green; STATE gained exactly one bullet.
