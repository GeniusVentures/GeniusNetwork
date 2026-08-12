---
phase: 11-empirical-cross-machine-capture-run
verified: 2026-08-11T00:00:00Z
status: passed
score: 9/9 must-haves verified
behavior_unverified: 0
overrides_applied: 0
---

# Phase 11: Empirical Cross-Machine Capture Run Verification Report

**Phase Goal:** Real cross-hardware divergence statistics exist across the user's own machines (Mac + PC + a third), gathered using Phase 10's tooling with quantization still a no-op — a hands-on data-gathering step Phase 12's precision decision depends on. Per this phase's own D-01/D-03, the accepted scope is 2 machines (Mac + Windows), and ROADMAP.md/REQUIREMENTS.md wording was supposed to be reconciled to reflect that.
**Verified:** 2026-08-11
**Status:** passed
**Re-verification:** No — initial verification

This is a documentation/data-organization-only phase (no source code created or modified). Verification checked file existence, exact byte/text/number matches, and absence of dropped content — not code behavior.

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | `captures/` contains exactly 4 Mac/Windows `.cap` files + 2 diff JSONs (6 total), relocated from repo-root `caps/`, which no longer exists | ✓ VERIFIED | `ls` shows exactly 6 files: `diff-mnn-float.json`, `diff-render.json`, and 4 `.cap` files for `Fuus-Mac-mini.local---macOS` / `Mofu---Windows` × {mnn-float, render}. Repo-root `caps/` confirmed absent (`ls caps/` → "No such file or directory"). `caps/` was never git-tracked (`git log --all --diff-filter=A -- 'caps/*'` returns nothing), consistent with SUMMARY's "untracked, plain filesystem move" claim. |
| 2 | WSL/llvmpipe MNN-float `.cap` not present anywhere under `captures/`, not cited as measured data in `11-CAPTURE-RESULTS.md` | ✓ VERIFIED | Repo-wide search for `*Mofu---Linux*` and `*llvmpipe*` filenames returns zero matches. `11-CAPTURE-RESULTS.md`'s "Dropped WSL/MNN Capture" section names the file only in prose (as excluded), cites no numeric/boolean field from it — both embedded JSON blocks are Mac-vs-Windows only. |
| 3 | `11-CAPTURE-RESULTS.md` cites exact `maxAbsDelta`, `maxRelDelta`, `maxUlpDistance`, `percentExceedingThreshold` and the 3 hash-match booleans per-hash-type (not flattened) from both diff JSONs | ✓ VERIFIED | Read `captures/diff-mnn-float.json` and `captures/diff-render.json` directly and diff'd against the embedded JSON blocks in `11-CAPTURE-RESULTS.md` — byte-identical (`maxAbsDelta: 1.043081283569336e-07`, `maxRelDelta: 7.269731577252969e-05`, `maxUlpDistance: 768` for MNN-float; `contentHashMatch: true`/`combinedHashMatch: false`/all-zero deltas for render). `contentHashMatch`, `chunkHashesMatch`, `combinedHashMatch` reported as 3 separate named fields, not merged. |
| 4 | `11-CAPTURE-RESULTS.md` states the 2-machine scope decision (D-01) and dropped-WSL rationale (D-04) as their own required sections | ✓ VERIFIED | Document has dedicated "## Scope Decision" and "## Dropped WSL/MNN Capture" H2 sections (lines 13, 21), each restating the D-01/D-04 substance, not a footnote. |
| 5 | `11-CAPTURE-RESULTS.md` identifies both machines using exact `.cap`-filename labels `Fuus-Mac-mini.local---macOS` and `Mofu---Windows` | ✓ VERIFIED | Both exact strings present verbatim in the "Machines and Fixtures" section and reused throughout. |
| 6 | ROADMAP.md Phase 11 SC1 and REQUIREMENTS.md QUANT-04 both read approximately "2 distinct physical machines"/"2-machine data" with the software-rasterizer-exclusion caveat, replacing stale "3" wording | ✓ VERIFIED | ROADMAP.md line 90 (SC1): "at least 2 distinct physical machines, including the user's Mac and PC... A third machine's only available Vulkan device was a software rasterizer — already excluded project-wide by `RenderProcessor::IsAcceptable()`'s device-type gate — so the dataset stays 2-machine..." ROADMAP.md line 85 (Phase Details Goal line — the specific line the task called out): "(Mac + PC) — a third machine's only available device was a software rasterizer, excluded per this phase's scope decision". REQUIREMENTS.md line 27 (QUANT-04): "empirical ≥2-machine data (Mac + Windows; a third machine's only available device was a software rasterizer, excluded per Phase 11's scope decision)". REQUIREMENTS.md line 84 (Phase 11 traceability note): "run Phase 10's tooling on ≥2 real machines (Mac + Windows); a third machine's only available device was a software rasterizer, excluded per Phase 11's scope decision". Note: ROADMAP.md's top-level phase-list one-line summary bullet (line 44) still reads "Mac + PC + a third machine" — this was explicitly and correctly left out of scope by the plan/SUMMARY (Task 3 named only SC1 + the Phase Details Goal line as in-scope edits) and is documented as a known residual inconsistency, not a hidden gap. |
| 7 | `RenderProcessor::IsAcceptable()` unmodified — this phase touches no SuperGenius/SGProcessingManager source file | ✓ VERIFIED | `git show --stat` on all 3 task commits (`187f863`, `a8054c3`, `150f7dc`) shows only `.planning/` paths touched; grep for "SuperGenius\|SGProcessingManager" across all 3 commit diffs returns zero matches. |
| 8 | No new `capture_harness`/`capture_diff` run performed — existing 2 diff JSONs already satisfy pairwise coverage | ✓ VERIFIED | `.cap`/JSON file timestamps (17:28–17:34) predate the Task 1 relocation commit (20:04) and the phase's formal execution window (per SUMMARY, 00:03–00:08 the next calendar day); file byte-sizes and content are consistent with a plain relocation, not a re-capture. No capture-tool invocation evidence anywhere in the 3 task commits. |
| 9 | STATE.md's "Operator Next Steps" no longer instructs gathering a third machine's captures; "Pending Todos" cross-reference also corrected | ✓ VERIFIED | `grep -n "Get the third machine\|formally kick off" STATE.md` → no matches (exit 1). "Operator Next Steps" (line 156) now reads "2-machine dataset (Mac + Windows) accepted per D-01; Phase 11 is not blocked on a third physical machine (D-02)." "Pending Todos" (line 98) now reads "...relocated into this phase's `captures/` directory per 11-01-PLAN.md Task 1" instead of "not yet moved into a phase-owned location". |

**Score:** 9/9 truths verified (0 present-but-behavior-unverified)

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `captures/` (6 files) | Phase-owned relocation of 4 `.cap` + 2 diff JSONs | ✓ VERIFIED | Exists, exactly 6 files, byte-identical content to what `11-CAPTURE-RESULTS.md` cites |
| `11-CAPTURE-RESULTS.md` | Written cross-hardware divergence statistics | ✓ VERIFIED | 113 lines, all required sections present, all cited numbers independently confirmed against source JSONs |
| `ROADMAP.md` | Phase 11 SC1 + Goal line reconciled to 2-machine scope | ✓ VERIFIED | Both target locations updated; discretionary phase-list bullet correctly documented as left untouched |
| `REQUIREMENTS.md` | QUANT-04 + Phase 11 traceability note reconciled | ✓ VERIFIED | Both target locations updated; VALD-01 and Phase 12/13 wording confirmed unchanged |
| `STATE.md` | Operator Next Steps + Pending Todos reconciled | ✓ VERIFIED | Both target locations updated per D-01/D-02 |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| `captures/diff-mnn-float.json`, `captures/diff-render.json` | `11-CAPTURE-RESULTS.md` | Verbatim-cited JSON fields | ✓ WIRED | Full JSON blocks embedded verbatim; byte-diff against source files confirms exact match |
| `11-CONTEXT.md` D-01/D-03/D-04 | ROADMAP.md Phase 11 SC1 + REQUIREMENTS.md QUANT-04 | Text substitution | ✓ WIRED | Both files carry the reconciled "≥2 distinct/real machines" + software-rasterizer caveat wording |
| `11-CONTEXT.md` D-02 | STATE.md Operator Next Steps + Pending Todos | Text substitution | ✓ WIRED | Stale third-machine instruction removed; superseding D-01/D-02 language present |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|--------------|--------|----------|
| (none) | 11-01-PLAN.md (`requirements: []`) | Phase 11 intentionally maps to zero of the 12 v2.1 requirements | ✓ SATISFIED | REQUIREMENTS.md line 84's traceability note still correctly states Phase 11 covers no requirement directly and explicitly names QUANT-04 as the downstream consumer, updated to the 2-machine wording. No orphaned requirements found — REQUIREMENTS.md's coverage table shows 12/12 mapped, 0 unmapped, all pointing to Phase 10/12/13, none to Phase 11 (as expected). |

No orphaned requirements: REQUIREMENTS.md's own "Mapped to phases: 12 / Unmapped: 0" table confirms Phase 11 was never expected to claim any requirement ID.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| ROADMAP.md / STATE.md | various (pre-existing, phase-12/13 rows) | `TBD` in "Plans: TBD" / "0/TBD" placeholders | ℹ️ Info | Standard GSD roadmap convention for not-yet-planned future phases (Phase 12, 13); predates this phase and is not a debt marker on Phase 11's own deliverable — no `#issue` reference needed since it's a template placeholder, not an unresolved TODO in phase-11-authored content |

No TBD/FIXME/XXX/TODO/HACK/PLACEHOLDER markers found in any of the 3 files/commits this phase actually authored or edited (`11-CAPTURE-RESULTS.md`, and the specific edited spans of ROADMAP.md/REQUIREMENTS.md/STATE.md). No blockers.

**Minor observation (not a gap):** STATE.md's "By Phase" summary table (line 52: "11 — Empirical Cross-Machine Capture Run | 0/TBD | Not started") is stale relative to the phase's actual completion — but this predates Phase 11 (Phase 10's row on line 51 has the identical staleness pattern despite Phase 10 being marked `[x]` complete in ROADMAP.md), was never in this plan's must-haves list, and Task 3's scope was explicitly limited to the "Operator Next Steps" and "Pending Todos" sections only. Not flagged as a gap.

### Human Verification Required

None. This phase is documentation/data-organization only; all must-haves are mechanically verifiable via file existence, exact text/number diffing, and git history — no runtime behavior, UI, or external service integration to assess.

### Gaps Summary

No gaps found. All 9 must-have truths, all 5 required artifacts, and all 3 key links are verified against the actual filesystem and git state (not merely SUMMARY.md's claims). The one wording location SUMMARY.md flagged as intentionally left untouched (ROADMAP.md's top-level phase-list bullet, line 44, still says "Mac + PC + a third machine") matches the plan's own documented scope boundary — Task 3's action text named only Success Criterion 1 and the Phase Details Goal line as required edits, and both of those were confirmed reconciled. This residual inconsistency was disclosed by the executor, not hidden, and does not block Phase 12.

---

*Verified: 2026-08-11*
*Verifier: Claude (gsd-verifier)*
