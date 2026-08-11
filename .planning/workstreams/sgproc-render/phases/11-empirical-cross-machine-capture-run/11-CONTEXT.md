# Phase 11: Empirical Cross-Machine Capture Run - Context

**Gathered:** 2026-08-11
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 11 is a hands-on data-gathering checkpoint, not a coding phase. No code is written. The deliverable is real cross-hardware divergence statistics — gathered via Phase 10's `capture_harness`/`capture_diff` tooling with quantization still a no-op stub — written down in a form Phase 12's normalization design can cite directly. This phase closes the loop between Phase 10 (built the tooling) and Phase 12 (needs real numbers to choose a normalization technique).

Ad-hoc data gathering already happened this session, ahead of formal phase kickoff: 5 `.cap` files + 2 `capture_diff` JSON reports exist in `caps/` at the repo root. This discussion formalizes that work's scope and turns it into the phase's actual deliverable.

</domain>

<decisions>
## Implementation Decisions

### Third-machine scope
- **D-01:** Phase 11 closes with 2 distinct real machines (Mac + Windows/"Mofu"), not the 3 the roadmap literally states. WSL's only available Vulkan device is `llvmpipe` (Mesa software rasterizer, `type=CPU`) — not real hardware, and exactly the software-Vulkan-ICD tier Phase 4's D-31 already excludes project-wide. Rather than loosen `RenderProcessor::IsAcceptable()` (which would affect `CanExecute()`/CI/production everywhere, not just this one box), the render dataset stays Mac+Windows only.
- **D-02:** The STATE.md "Operator Next Steps" line ("get the third machine's .cap files … before Phase 11 can close out") predates this decision and is stale — superseded by D-01. A genuine third physical machine can still be added later if one becomes available, but Phase 11 is not blocked on it.
- **D-03:** ROADMAP.md Phase 11 Success Criterion 1 ("at least 3 distinct physical machines") and REQUIREMENTS.md QUANT-04 ("≥3-machine data") must be updated during this phase's plan to read "≥2 distinct physical machines" (plus the labeled software-rasterizer caveat from D-04). This is a planned doc edit, not scope creep — it's reconciling the roadmap's literal text with the scope decision made here.

### WSL/MNN curiosity handling
- **D-04:** The already-captured WSL/llvmpipe MNN-float `.cap` (`xhw-mnn-float_Mofu---Linux_*.cap`) is dropped entirely — not cited in the results doc, not carried into the phase-owned capture directory. Rationale (user-confirmed): MNN has no device-type filter, so it silently ran on the software rasterizer; RenderProcessor's `IsAcceptable()` already excludes that device class, so render never produced a WSL capture at all. Comparing a software rasterizer against real GPUs isn't apples-to-apples, so it doesn't belong in the 2-machine hardware dataset Phase 12 will cite.
- **D-05:** Only Mac and Windows data survives into Phase 11's deliverable, for both fixtures.

### Pairwise diff coverage
- **D-06:** With WSL dropped, the complete pairwise set is exactly 1 diff per fixture (Mac vs Windows) — already produced: `caps/diff-mnn-float.json`, `caps/diff-render.json`. No further captures or diffs are needed to close this phase.
- **D-07:** Same-node repeat-run stability (ROADMAP SC2) does not need a separate re-verification step — `capture_harness`'s built-in `--repeat` self-check (default 3, minimum 2, aborts and writes no file on any divergence) already guarantees this by construction for every `.cap` file that exists. Any file present in `caps/` already passed this check.

### Results artifact & file location
- **D-08:** Phase 11's deliverable is a new phase-owned doc, `11-CAPTURE-RESULTS.md`, in this phase directory. It must cite the exact numbers from `caps/diff-mnn-float.json` and `caps/diff-render.json` (maxAbsDelta, maxRelDelta, maxUlpDistance, percentExceedingThreshold, hash-match booleans), state the 2-machine scope decision (D-01) and the dropped-WSL rationale (D-04), and be written so Phase 12's planning can cite specific captured numbers rather than a guessed constant (satisfies ROADMAP SC4 / QUANT-04).
- **D-09:** The raw evidence files move from repo-root `caps/` into a phase-owned location: `.planning/workstreams/sgproc-render/phases/11-empirical-cross-machine-capture-run/captures/` (all `.cap` files except the dropped WSL one, plus both diff JSONs). The repo-root `caps/` directory is deleted once the move is confirmed.

### Claude's Discretion
- Exact prose/formatting of `11-CAPTURE-RESULTS.md` — the required content is D-08's list; structure (tables vs. prose, ordering) is left to planning/execution.
- Whether the dropped WSL `.cap` file is deleted outright or archived somewhere untracked — D-04/D-09 only require it not appear in the phase-owned `captures/` directory or the results doc.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 11 scope and dependency chain
- `.planning/workstreams/sgproc-render/ROADMAP.md` — Phase 11 goal, success criteria (needs SC1 wording updated per D-03), and the hard 10→11→12→13 dependency note
- `.planning/workstreams/sgproc-render/REQUIREMENTS.md` — QUANT-04 (needs wording updated per D-03), Phase 11's "maps to zero requirements" note

### Prior session state (source of the decisions captured here)
- `.planning/workstreams/sgproc-render/STATE.md` — "Key Decisions (v2.1 Roadmap)" and "Pending Todos" sections record the 2/3-machine decision and WSL/llvmpipe rationale this discussion formalized; "Operator Next Steps" is superseded by D-02

### Phase 10 tooling this phase exercises (no code changes here, but behavior matters for planning)
- `.planning/workstreams/sgproc-render/phases/10-capture-harness-diff-tool-quantization-stub/10-05-PLAN.md` — `capture_harness`/`capture_diff` CLI flags, including `--repeat`'s self-check behavior (D-07) and `capture_diff`'s JSON output schema (fields cited in D-08)
- `.planning/workstreams/sgproc-render/phases/10-capture-harness-diff-tool-quantization-stub/10-CONTEXT.md` — Phase 10's own context, for any prior decisions about capture file format or fixture selection

### Raw evidence (to be relocated per D-09)
- `caps/` at repo root — 5 `.cap` files + 2 diff JSONs from this session's ad-hoc capture run; moves to this phase's `captures/` subdirectory (WSL MNN-float `.cap` excluded per D-04)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `capture_harness` / `capture_diff` CLI tools (built in Phase 10, `SGProcessingManager/tools/capture/`) — this phase only *runs* them, no new code

### Established Patterns
- `RenderProcessor::IsAcceptable()` (D-31, Phase 4) already excludes software Vulkan ICDs (`llvmpipe`, `type=CPU`) project-wide — this is why render has no WSL capture and why D-01 doesn't propose loosening it just for this one box
- `capture_harness --repeat` (default 3, min 2) bakes same-node stability verification into every successful `.cap` file by construction — no separate verification step needed (D-07)

### Integration Points
- None — this phase produces a document and relocates files; it does not touch `SGProcessingManager` source

</code_context>

<specifics>
## Specific Ideas

Machine identities already captured in existing `.cap` filenames: `Fuus-Mac-mini.local---macOS` and `Mofu---Windows` (plus the dropped `Mofu---Linux`/WSL one). `11-CAPTURE-RESULTS.md` should use these exact machine labels for traceability back to the raw `.cap` files.

</specifics>

<deferred>
## Deferred Ideas

- Loosening `RenderProcessor::IsAcceptable()` to permit software Vulkan devices — explicitly rejected (D-01) as out of scope; would be a project-wide capability-gate change affecting `CanExecute()`/CI/production, not a Phase 11 concern.
- Adding a genuine third physical machine's captures — not blocking (D-02), but can be folded in later if a real device becomes available; would be a small follow-up to `11-CAPTURE-RESULTS.md` rather than reopening Phase 11's scope decision.

### None — discussion stayed within phase scope

</deferred>

---

*Phase: 11-Empirical Cross-Machine Capture Run*
*Context gathered: 2026-08-11*
