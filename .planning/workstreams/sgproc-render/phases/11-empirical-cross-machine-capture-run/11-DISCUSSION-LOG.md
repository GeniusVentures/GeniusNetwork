# Phase 11: Empirical Cross-Machine Capture Run - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-08-11
**Phase:** 11-Empirical Cross-Machine Capture Run
**Areas discussed:** Third-machine scope, WSL/MNN curiosity handling, Pairwise diff coverage, Results artifact & file location

---

## Third-machine scope

| Option | Description | Selected |
|--------|-------------|----------|
| Close at 2 machines now | Accept Mac+Windows as the hardware dataset; update ROADMAP.md SC1 and REQUIREMENTS.md QUANT-04 wording from "≥3" to "≥2 + labeled curiosity"; treat STATE.md's "get the third machine" line as stale | ✓ |
| Keep pursuing a real 3rd machine | Leave Phase 11 open until a genuine GPU-capable third machine appears; roadmap wording stays at "≥3" | |
| Time-box it | Try for a real 3rd machine for a specific window, fall back to 2-machine close-out if none materializes | |

**User's choice:** Close at 2 machines now (recommended option).
**Notes:** Confirms STATE.md's "accept 2/3 machines" decision as the operative one; the later "Operator Next Steps" line about getting a third machine's caps predates that decision.

---

## WSL/MNN curiosity handling

| Option | Description | Selected |
|--------|-------------|----------|
| Keep as labeled curiosity | Include WSL/llvmpipe MNN-float numbers in the results doc under a clearly separate "not part of the 2-machine dataset" section | |
| Drop it entirely | Exclude the WSL capture and its numbers entirely; only Mac+Windows survives | ✓ |
| Keep the file, omit from the doc | Archive the .cap file but never cite its numbers | |

**User's choice:** Drop it entirely (free-text response, mapped to this option).
**Notes:** User's exact words: "MNN allows run on llvmpipe CPU, so that capture came from that. We can ignore it. Render pipeline won't allow use of llvmpipe CPU run." Confirms MNN has no device-type filter (ran silently on software rasterizer) while RenderProcessor::IsAcceptable() already excludes that device class — so render never had a WSL capture to begin with.

---

## Pairwise diff coverage

| Option | Description | Selected |
|--------|-------------|----------|
| Sufficient as-is | 2 diffs (1 per fixture, Mac vs Windows) is the complete pairwise set for a 2-machine dataset given WSL is dropped | ✓ |
| Re-run with more --repeat iterations first | Re-verify same-node stability explicitly before closing, even though capture_harness already guarantees it by construction | |
| Something else | User describes what's missing | |

**User's choice:** Sufficient as-is (recommended option).
**Notes:** capture_harness's built-in `--repeat` self-check (default 3, min 2, aborts on divergence) already guarantees same-node stability for every existing `.cap` file — no separate re-verification needed.

---

## Results artifact & file location

| Option | Description | Selected |
|--------|-------------|----------|
| New 11-CAPTURE-RESULTS.md | Phase-owned doc citing exact diff numbers, scope decision, and dropped-WSL rationale — the file Phase 12 cites directly | ✓ |
| Fold into STATE.md only | No new doc; expand STATE.md's existing Key Decisions/Pending Todos sections | |
| Something else | User describes preferred format/location | |

**User's choice:** New 11-CAPTURE-RESULTS.md (recommended option).
**Notes:** Follow-up question confirmed the raw `.cap`/diff-JSON files also move from repo-root `caps/` into this phase's directory (`captures/` subfolder), with the repo-root `caps/` dir deleted after — "Move into phase dir (Recommended)" selected.

---

## Claude's Discretion

- Exact prose/formatting of `11-CAPTURE-RESULTS.md` (tables vs. prose, ordering).
- Whether the dropped WSL `.cap` file is deleted outright or archived untracked — only requirement is it doesn't appear in the phase-owned `captures/` directory or the results doc.

## Deferred Ideas

- Loosening `RenderProcessor::IsAcceptable()` to permit software Vulkan devices — explicitly rejected as out of scope (would be a project-wide capability-gate change, not a Phase 11 concern).
- Adding a genuine third physical machine's captures later, if one becomes available — not blocking Phase 11's close-out; would be a small follow-up rather than reopening the scope decision.
