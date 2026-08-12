---
phase: 13-re-validation-scope-boundary-documentation
verified: 2026-08-12T21:43:46Z
status: gaps_found
score: 3/4 must-haves verified
behavior_unverified: 0
overrides_applied: 0
gaps:
  - truth: "ROADMAP Phase 13 SC1 / VALD-01: Re-running capture_harness + capture_diff with real quantization active across ≥2 distinct physical machines confirms matching post-normalization processor-level result/chunk hashes for BOTH the render fixture and the MNN fixture"
    status: failed
    reason: "Empirically re-confirmed FALSE for the MNN float32 fixture. Fresh capture_diff run (captures/diff-mnn-float.json, Mac-vs-Windows, Phase 12 real quantization active) reports contentHashMatch: false and 12 of 15 chunkHashesMatch entries false (only indices 8, 10, 14 true). Render uint8 fixture (captures/diff-render.json) does satisfy the target: contentHashMatch: true, all deltas 0. This is honestly documented by the executor in 13-SCOPE-BOUNDARY.md's 'Open Gap Against SC1' section and REQUIREMENTS.md's VALD-01 traceability status ('Partial'), but the literal SC1/VALD-01 truth requires BOTH fixtures to match, and it does not."
    artifacts:
      - path: ".planning/workstreams/sgproc-render/phases/13-re-validation-scope-boundary-documentation/captures/diff-mnn-float.json"
        issue: "contentHashMatch: false; chunkHashesMatch has 12/15 false entries — real empirical divergence, not a documentation or wiring defect"
      - path: ".planning/workstreams/sgproc-render/phases/13-re-validation-scope-boundary-documentation/13-SCOPE-BOUNDARY.md"
        issue: "Correctly and honestly documents the gap (verified accurate against the raw JSON below) — the artifact itself is not defective, but it records that the milestone's literal acceptance criterion is not yet met for one of two fixtures"
    missing:
      - "A quantization-constant or algorithm fix for the MNN float32 path (e.g. a wider grid step, or per-element boundary/tie-break handling) that closes the remaining 12/15 chunk-hash divergence, followed by a re-run of capture_harness/capture_diff producing contentHashMatch: true for the MNN fixture"
      - "An explicit operator/maintainer decision on whether a render-only pass (with MNN's gap tracked as known follow-up work) is an acceptable stopping point for the v2.1 milestone, or whether VALD-01 must be fully closed before milestone completion"
---

# Phase 13: Re-Validation & Scope Boundary Documentation Verification Report

**Phase Goal:** The milestone's literal acceptance criterion is empirically reconfirmed with real quantization active, and the milestone's scope boundary is written down explicitly: this milestone makes hash comparison cross-hardware tolerant, it does not fix `ProcessingValidationCore::ValidateResults`'s concatenation bug and does not build cross-node consensus/redundant-execution plumbing — both stay explicitly out of scope per REQUIREMENTS.md's Out of Scope table.
**Verified:** 2026-08-12T21:43:46Z
**Status:** gaps_found
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth (ROADMAP SC) | Status | Evidence |
|---|------|--------|----------|
| 1 | SC1: fresh capture_harness+capture_diff run (real quantization active, 2 machines) confirms matching processor-level hashes for **both** render and MNN fixtures | ✗ FAILED | `captures/diff-mnn-float.json`: `contentHashMatch: false`, `chunkHashesMatch` 12/15 false. `captures/diff-render.json`: `contentHashMatch: true`, all deltas 0. Render passes; MNN does not — SC1 requires both. |
| 2 | SC2: SECV-01 counter-test re-run at final precision still passes | ✓ VERIFIED | `13-SECV01-RERUN.txt` verbatim: both `MnnCorruptedModelStillDiverges` and `RenderWrongShaderConstantStillDiverges` report `[ OK ]`/`PASSED`, `100% tests passed, 0 tests failed`. Confirmed `secv01_counter_test.cpp`, its CMakeLists.txt, and both fixtures are byte-identical since Phase 12 (`git diff --stat` empty). |
| 3 | SC3: written document records the explicit scope boundary (hash cross-hardware tolerant; ValidateResults bug unfixed; no consensus plumbing built; not "verification"/"consensus-ready") | ✓ VERIFIED | `13-SCOPE-BOUNDARY.md` "Scope Boundary" section quotes REQUIREMENTS.md's Out of Scope table **verbatim** for both excluded items — confirmed by direct text comparison against `REQUIREMENTS.md` lines 54-55 (byte-for-byte match). Explicit "not verification/consensus-ready" sentence present, matching ROADMAP SC3's own wording. |
| 4 | SC4: final normalization constants + empirical derivation (citing Phase 11's numbers) documented | ✓ VERIFIED | `13-SCOPE-BOUNDARY.md` SC4 section cites `S = 2^20 (1048576.0f)`, canonicalization bit patterns (`0x7FC00000`, `0x7F800000`/`0xFF800000`, `0x00000000`) — confirmed present verbatim in `SuperGenius/SGProcessingManager/include/util/quantization.hpp`'s doc comments (source of truth, unmodified). Phase 11 numbers (`maxAbsDelta ≈ 1.043081283569336e-07`, `maxRelDelta ≈ 7.269731577252969e-05`, `maxUlpDistance = 768`) cited verbatim, matching the numbers baked into the plan's own must_haves. |

**Score:** 3/4 truths verified (0 present-but-behavior-unverified)

**Note on truth #1:** This is not an UNCERTAIN/judgment-call classification. The executor ran the actual empirical test (`capture_diff` against fresh real-quantization `.cap` files) and it produced a concrete, machine-checkable, unfavorable result (`contentHashMatch: false`). This is a definitive FAILED truth, not a case needing human interpretation of ambiguous evidence — the phase's own honest reporting confirms the same conclusion this verification independently reaches from the raw JSON.

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `captures/xhw-mnn-float_*.cap` (x2), `captures/xhw-render_*.cap` (x2) | 4 fresh .cap files, real quantization active | ✓ VERIFIED | All 4 present, timestamped 2026-08-12 (distinct from Phase 11's 2026-08-11 files). `md5sum` comparison against Phase 11's captures confirms all 4 content hashes differ (genuinely fresh, not stale/reused), despite matching byte sizes (expected — same chunk/record counts). |
| `captures/diff-mnn-float.json` | Fresh Mac-vs-Windows processor-level diff, MNN fixture | ✓ VERIFIED (data present, but shows a failing result) | Valid JSON, contains `contentHashMatch`/`chunkHashesMatch`/`combinedHashMatch`/delta fields, matches `capture_diff.cpp`'s actual field-computation logic (verified against source, lines 279-368). |
| `captures/diff-render.json` | Fresh Mac-vs-Windows processor-level diff, render fixture | ✓ VERIFIED | Valid JSON; `contentHashMatch: true`, all deltas 0. |
| `13-SECV01-RERUN.txt` | Verbatim `ctest -V` output, SECV-01 re-run | ✓ VERIFIED | Present, both sub-tests PASSED, verbatim console capture including timestamps/device enumeration (NVIDIA RTX 4070 Ti SUPER). |
| `13-SCOPE-BOUNDARY.md` | Combined re-validation results + scope-boundary record | ✓ VERIFIED (content honest, but records goal not fully met) | Present, cites both diff JSONs verbatim, cites SECV-01 pass, quotes Out of Scope table verbatim, documents SC4 constants + derivation, and explicitly states the MNN open gap rather than rounding it away. |
| `REQUIREMENTS.md` (VALD-01 wording + status) | "≥2 distinct physical machines" / "processor-level result/chunk hash" wording; VALD-01 marked Partial | ✓ VERIFIED | Line 35: wording corrected exactly as D-02/D-04 mandated. Line 76 (Traceability table): `VALD-01 | Phase 13 | Partial — render OK, MNN open gap (see 13-SCOPE-BOUNDARY.md)`. Checkbox remains `[ ]` unchecked — correctly not marked complete, consistent with the partial result. |
| `ROADMAP.md` (Phase 13 SC1 wording) | Same two wording corrections | ✓ VERIFIED | Phase 13 SC1 (line 125) reads "≥2 distinct physical machines" / "processor-level result/chunk hashes". Goal/SC2/SC3/SC4 unchanged, confirmed by re-reading full section. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| Phase 12 real quantization (`76f6ae6`) + SECV-01 commits | fresh `.cap` files | rebuilt `capture_harness`, run on both machines | ✓ WIRED (asserted, `human_judgment: true` in 13-01's coverage) | Content-hash diff against Phase 11's stub-era captures confirms these are NOT reused stale files (all 4 differ). Rebuild-against-Phase-12-commits precondition itself is asserted via the checkpoint's user resume-signal, per the plan's own threat model (T-13-02) — not independently re-derivable from `.cap` bytes alone. Accepted as designed (checkpoint:human-action task). |
| `captures/*.cap` | `captures/diff-*.json` | `capture_diff --a/--b --json-output` | ✓ WIRED | Confirmed `capture_diff.cpp` computes exactly the `contentHashMatch`/`chunkHashesMatch`/`combinedHashMatch` fields present in the JSON output (source-code cross-check, lines 279-368). |
| `diff-*.json` + `13-SECV01-RERUN.txt` | `13-SCOPE-BOUNDARY.md` | verbatim-cited JSON fields + ctest lines | ✓ WIRED | Every numeric value and PASSED/OK line quoted in `13-SCOPE-BOUNDARY.md` matches the source files byte-for-byte (cross-checked directly). |
| `REQUIREMENTS.md` Out of Scope table | `13-SCOPE-BOUNDARY.md` Scope Boundary section | quoted canonical wording | ✓ WIRED | Both quoted excerpts (`ValidateResults`'s concatenation bug; cross-node consensus/redundant-execution plumbing) are byte-for-byte identical to `REQUIREMENTS.md` lines 54-55. |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|---|---|---|---|---|
| VALD-01 | 13-03-PLAN.md | Both fixtures produce matching processor-level hashes cross-machine post-quantization | ✗ PARTIAL / BLOCKED | Render fixture satisfies it; MNN fixture does not (12/15 chunk hashes diverge). Correctly reflected as "Partial" (not "Complete") in REQUIREMENTS.md's traceability table and left unchecked. No orphaned requirements found for this phase (13-01/13-02 correctly declare `requirements: []`; VALD-01 is 13-03's sole declared requirement and is the only ID mapped to Phase 13 in REQUIREMENTS.md's traceability table). |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `.planning/workstreams/sgproc-render/ROADMAP.md` | Progress table, Phase 13 row (~line 159) and phase-list summary bullet (~line 46) | Phase 13 marked plain `Complete` with no gap qualifier, inconsistent with this same table's own precedent of flagging partial states (e.g. "Complete (gaps open)" for Phase 04, "Complete (override)" for Phases 06-08) | ⚠️ Warning | Not a blocker — REQUIREMENTS.md's own VALD-01 traceability row correctly says "Partial" and `13-SCOPE-BOUNDARY.md` is fully honest. But a reader scanning only the ROADMAP Progress table (rather than the requirements traceability table or the phase's own SC1 text) could get a falsely complete impression of Phase 13. Recommend adding a `(VALD-01 partial — MNN open gap)` qualifier to both the phase-list bullet and Progress-table row, matching the existing convention used for Phases 04/06/07/08. |

No debt markers (`TBD`/`FIXME`/`XXX`/`TODO`/`HACK`/`PLACEHOLDER`) found in any file this phase modified.

### Human Verification Required

None — SC2/SC3/SC4 are fully verified by direct evidence cross-check, and SC1's failure is a definitive, machine-checked empirical result, not an item requiring human judgment to interpret. This routes to **gaps_found**, not **human_needed**, under the standard decision tree (a FAILED truth takes precedence).

### Gaps Summary

Phase 13 executed its own scope faithfully and honestly: it re-ran the capture/diff tooling with Phase 12's real quantization active, re-confirmed SECV-01, wrote the scope-boundary document, and reconciled the REQUIREMENTS.md/ROADMAP.md wording exactly as planned — all three plans' own must_haves for tooling execution, documentation completeness, and honest reporting are met. The gap is not in what the phase built or documented; it is that the empirical measurement itself falsifies the literal ROADMAP Phase 13 SC1 / VALD-01 truth for one of the two required fixtures. The MNN float32 fixture's processor-level hash does not yet match cross-hardware post-quantization (`contentHashMatch: false`, 12/15 `chunkHashesMatch` false), even though Phase 12's real quantization is active and its grid step was sized with a stated ~10x margin over Phase 11's pre-quantization measured delta.

Per the goal-backward decision tree, a FAILED must-have truth routes to `gaps_found` (not `human_needed`) regardless of how well-documented and honestly-reported the failure is — the phase goal ("the milestone's literal acceptance criterion is empirically reconfirmed") is not fully achieved while one of its two required fixtures still diverges. This is a genuine, unresolved engineering gap (likely requiring a quantization-constant/algorithm adjustment for the MNN path, per `13-SCOPE-BOUNDARY.md`'s own preliminary hypothesis about grid-boundary tie-breaks) that should route through `/gsd-plan-phase --gaps` for a closure plan, rather than being treated as an operator-acceptable stopping point without an explicit decision. If the maintainer instead judges "render-only, MNN gap tracked as follow-up" to be an acceptable stopping point for this milestone, that should be recorded as an explicit override in this VERIFICATION.md's frontmatter (see the override-suggestion mechanism) rather than silently passed.

**This looks like it could be intentional/acceptable to the operator**, given the phase's own honest framing and the fact SC2-SC4 are fully satisfied. To accept this deviation instead of routing to gap-closure planning, add to this file's frontmatter:

```yaml
overrides:
  - must_have: "SC1: capture_diff confirms matching processor-level hashes for both the render fixture and the MNN fixture"
    reason: "Render fixture fully matches; MNN fixture's remaining 12/15 chunk-hash divergence is accepted as a tracked, documented follow-up gap rather than a phase-blocking defect"
    accepted_by: "{name}"
    accepted_at: "{ISO timestamp}"
```

---

*Verified: 2026-08-12T21:43:46Z*
*Verifier: Claude (gsd-verifier)*
