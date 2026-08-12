# Phase 13: Re-Validation & Scope Boundary Documentation - Pattern Map

**Mapped:** 2026-08-12
**Files analyzed:** 3 (1 new doc, 2 doc edits)
**Analogs found:** 3 / 3

This is a data-gathering + doc-edit phase, structurally identical to Phase 11. No production source files are created or modified — `capture_harness`, `capture_diff`, and `secv01_counter_test.cpp` are re-run unmodified against Phase 12's rebuilt binaries. The only artifacts are: one new phase-owned results/scope-boundary document, and scoped text edits to two already-existing cross-phase docs (`REQUIREMENTS.md`, `ROADMAP.md`).

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|--------------------|------|-----------|-----------------|----------------|
| `.planning/workstreams/sgproc-render/phases/13-re-validation-scope-boundary-documentation/13-SCOPE-BOUNDARY.md` (new) | doc/results-record | batch (offline capture-and-cite) | `.planning/workstreams/sgproc-render/phases/11-empirical-cross-machine-capture-run/11-CAPTURE-RESULTS.md` | exact |
| `.planning/workstreams/sgproc-render/REQUIREMENTS.md` (VALD-01 line edit) | config/spec doc | transform (scoped text substitution) | Phase 11's edit to `REQUIREMENTS.md`'s QUANT-04 line + Phase-11-traceability-note (11-01-PLAN.md Task 3) | exact |
| `.planning/workstreams/sgproc-render/ROADMAP.md` (Phase 13 SC1 line edit) | config/spec doc | transform (scoped text substitution) | Phase 11's edit to `ROADMAP.md`'s Phase 11 SC1 + Goal line (11-01-PLAN.md Task 3) | exact |
| (re-run only, no file changes) `capture_harness`/`capture_diff` on rebuilt binaries | tool invocation | batch/file-I/O | Phase 11's own use of the same tools (11-01-PLAN.md Task 1/2's `read_first` of `caps/diff-*.json`) | exact |
| (re-run only, no file changes) `secv01_counter_test.cpp` via CTest | test | request-response (assert-and-report) | Phase 12's own creation/use of the same test file, cited via `12-CONTEXT.md` D-10..D-13 | exact — but do not modify, cite the pass only |

## Pattern Assignments

### `.planning/workstreams/sgproc-render/phases/13-re-validation-scope-boundary-documentation/13-SCOPE-BOUNDARY.md` (new doc)

**Analog:** `.planning/workstreams/sgproc-render/phases/11-empirical-cross-machine-capture-run/11-CAPTURE-RESULTS.md` (114 lines, read in full)

**Frontmatter/header pattern** (lines 1-11 of the analog):
```markdown
---
phase: 11-empirical-cross-machine-capture-run
captured: 2026-08-11
status: 2-machine dataset (Mac + Windows)
---

# Phase 11: Empirical Cross-Machine Capture Run — Capture Results

**Phase Goal:** Real cross-hardware divergence statistics, gathered via Phase 10's `capture_harness`/`capture_diff` tooling with quantization still a no-op stub, written down in a form Phase 12's normalization design can cite directly.
**Captured:** 2026-08-11
**Status:** 2-machine dataset (Mac + Windows) — see Scope Decision below.
```
Apply the same shape to `13-SCOPE-BOUNDARY.md`, but the header must reflect Phase 13's real-quantization status (not "no-op stub") and should name this doc's dual purpose (results + scope boundary) per CONTEXT.md D-09.

**Scope-decision section pattern** (lines 13-19): a named `## Scope Decision` (or equivalent) heading stating the machine-count acceptance in plain prose, citing the specific decision IDs (D-01/D-02/D-03 in the analog → this phase's D-01/D-02). Reuse verbatim structure:
```markdown
## Scope Decision

Phase 11 closes with **2 distinct real machines** — the user's Mac (`Fuus-Mac-mini.local---macOS`) and PC (`Mofu---Windows`) — not the 3 originally stated in the roadmap.

WSL was attempted as a candidate third machine. ...

This decision is recorded as D-01 ... in `11-CONTEXT.md`.
```
For Phase 13, this becomes a statement that the same accepted 2-machine dataset from Phase 11 is being reused/re-run (per D-01), with a forward reference to `13-CONTEXT.md`'s own D-01/D-02.

**Verbatim JSON-embedding pattern** (lines 41-105, the two fixture subsections `## MNN Float32 Fixture` and `## Render Uint8 Fixture`): each fixture gets its own heading, a fenced ```json block with the *exact*, unrounded `capture_diff` output pasted verbatim, followed by a "**Interpretation:**" paragraph that names each JSON field by its literal key and gives the rounded human-readable number in parentheses next to the exact value. Example shape to replicate exactly for Phase 13's re-capture output:
```markdown
## MNN Float32 Fixture

Full verbatim contents of `captures/diff-mnn-float.json` (Mac vs Windows):

\`\`\`json
{
  "chunkHashesMatch": [ ... ],
  "combinedHashMatch": false,
  "contentHashMatch": false,
  "elementCount": 512,
  "elementType": "float32",
  "maxAbsDelta": 1.043081283569336e-07,
  "maxRelDelta": 7.269731577252969e-05,
  "maxUlpDistance": 768,
  "percentExceedingThreshold": 0.0,
  "sizeMismatch": false
}
\`\`\`

**Interpretation:** ...
```
Phase 13's version must be sourced from the fresh `captures/` subdirectory JSONs (per this phase's D-06: `.planning/workstreams/sgproc-render/phases/13-re-validation-scope-boundary-documentation/captures/`, NOT Phase 11's `captures/`), and per D-03 the interpretation prose must explicitly name the **processor-level** `ProcessingResult.hash`/chunk-hash fields being compared — not `combinedHash`/`manifestHash` — since this phase's whole point is the corrected hash-layer distinction.

**Closing "Implications" section pattern** (lines 107-114, `## Implications for Phase 12`): a short closing section connecting the numbers to the next artifact/requirement. For Phase 13, replace with sections satisfying CONTEXT.md D-09's required content list directly: SC1 processor-level hash match citation, SC2 SECV-01 fresh-pass citation, and SC4's final normalization constants + their empirical derivation (citing Phase 11's exact numbers verbatim, reusing the analog's own already-cited values: `maxAbsDelta ≈ 1.043081283569336e-07`, `maxRelDelta ≈ 7.269731577252969e-05`, `maxUlpDistance = 768`).

**SECV-01 citation pattern (no direct analog in 11-CAPTURE-RESULTS.md — new content, but sourced from):** `SuperGenius/test/src/processing_conformance_security/secv01_counter_test.cpp` (read this file's test name/assertions before writing the pass citation) and `.planning/workstreams/sgproc-render/phases/12-quantization-normalization-implementation/12-CONTEXT.md` D-10 through D-13 for the exact mechanism/assertion shape to describe accurately (do not invent new assertion semantics — cite what the existing test actually checks).

**Scope-boundary language source (for the explicit-out-of-scope section D-09 requires):** `.planning/workstreams/sgproc-render/REQUIREMENTS.md` lines 47-57 (`## Out of Scope` table) — reuse this table's exact wording for the three items D-09 names: (1) `ProcessingValidationCore::ValidateResults`'s concatenation bug remains unfixed, (2) no cross-node consensus/redundant-execution plumbing was built, (3) hash comparison is now cross-hardware tolerant (this milestone's actual scope, contrasted against the two "not done" items). Quote the Out-of-Scope table's own phrasing rather than paraphrasing, to stay consistent with the requirements doc's canonical wording.

---

### `.planning/workstreams/sgproc-render/REQUIREMENTS.md` (VALD-01 wording edit, D-02/D-04)

**Analog:** Phase 11's own `REQUIREMENTS.md` QUANT-04 edit, executed by `11-01-PLAN.md` Task 3 (read in full above).

**Current text to edit** (REQUIREMENTS.md line 35, read directly):
```markdown
- [ ] **VALD-01**: The same render fixture and the same MNN fixture, run on ≥3 different machines (including the user's Mac and PC), produce matching post-normalization combined hashes
```

**Edit-tool scoped-replacement pattern** (mirrors 11-01-PLAN.md Task 3's exact instruction style — "Use the Edit tool (scoped replacement) ... never Write a whole-file rewrite of either, since both contain many unrelated phase entries outside this plan's scope"): apply a targeted `Edit` to this single line only. Per CONTEXT.md D-02/D-03/D-04, the corrected line must read approximately:
```markdown
- [ ] **VALD-01**: The same render fixture and the same MNN fixture, run on ≥2 distinct physical machines (including the user's Mac and PC; a third machine was attempted but excluded — see 13-SCOPE-BOUNDARY.md), produce matching post-normalization **processor-level result/chunk hashes** (not `ProcessOutput.combinedHash`/`ExecutionManifest.manifestHash`, which bake in machine-specific `executorIdentity`/`gpuMemoryUsedBytes` by design — see `SGProcessingManager/src/processingbase/ProcessingManager.cpp:1500-1510` and `12-CONTEXT.md` D-01/D-02)
```
Exact prose is Claude's discretion per CONTEXT.md; the two required landing points are "≥2 machines" and "processor-level result/chunk hash" (D-02/D-04).

**Traceability table note** (line 76, unchanged status marker but part of the same file): `| VALD-01 | Phase 13 | Pending |` — leave alone (status flips to Complete only after this phase's execution/verification, not during patterns/planning).

---

### `.planning/workstreams/sgproc-render/ROADMAP.md` (Phase 13 SC1 wording edit, D-02/D-04)

**Analog:** Phase 11's own `ROADMAP.md` Phase 11 SC1 + Goal-line edit, executed by `11-01-PLAN.md` Task 3.

**Current text to edit** (ROADMAP.md lines 125, 46, read directly):
```markdown
1. Re-running `capture_harness` + `capture_diff` with real quantization active across ≥3 different machines (including the user's Mac and PC) confirms matching post-normalization combined hashes for both the render fixture and the MNN fixture.
```
and the Phase-list summary line:
```markdown
- [ ] **Phase 13: Re-Validation & Scope Boundary Documentation** - Re-run the ≥3-machine capture/diff cycle with real quantization active to confirm VALD-01, re-confirm SECV-01 at the final precision, and document the milestone's scope boundary
```

**Edit-tool scoped-replacement pattern** (same discipline as REQUIREMENTS.md above and as Phase 11's Task 3 precedent — scoped `Edit`, not whole-file `Write`): SC1's corrected text must land on "≥2 distinct physical machines" and "processor-level result/chunk hash(es)" per D-02/D-04, e.g.:
```markdown
1. Re-running `capture_harness` + `capture_diff` with real quantization active across ≥2 distinct physical machines (including the user's Mac and PC; a third machine attempted but excluded, see 13-SCOPE-BOUNDARY.md) confirms matching post-normalization **processor-level result/chunk hashes** for both the render fixture and the MNN fixture.
```
The Phase-13 one-line summary entry (line 46) should get the same "≥3-machine" → "≥2-machine" correction for internal consistency, mirroring how Phase 11's own Task 3 also touched its adjacent Goal-line wording as a "discretionary consistency fix in the same document" beyond the explicitly mandated line.

**Do NOT touch:** SC2/SC3/SC4 (lines 126-128) — those are unaffected by the D-02/D-04 wording fix and are the actual content Phase 13's execution must satisfy, not edit targets themselves.

## Shared Patterns

### Phase-owned results-doc convention
**Source:** `11-CAPTURE-RESULTS.md` structure (frontmatter block, Scope Decision section, per-fixture verbatim-JSON-plus-interpretation subsections, closing Implications section)
**Apply to:** `13-SCOPE-BOUNDARY.md` in full — this is the single dominant pattern for this phase's one new file.

### Scoped-Edit-not-Write discipline for cross-phase docs
**Source:** `11-01-PLAN.md` Task 3's explicit instruction: "Use the Edit tool (scoped replacement) on both files — never Write a whole-file rewrite of either, since both contain many unrelated phase entries outside this plan's scope."
**Apply to:** Both the `REQUIREMENTS.md` VALD-01 edit and the `ROADMAP.md` Phase 13 SC1 edit. Both files contain many unrelated phase/requirement entries; only the named lines (plus their immediately-adjacent stale-wording twins, per Phase 11's precedent of also fixing the adjacent Goal-line) should change.

### Verbatim-numeric-citation discipline
**Source:** `11-CAPTURE-RESULTS.md`'s embedded fenced JSON blocks (byte-for-byte, unrounded values, e.g. `1.043081283569336e-07` not `~1e-7`)
**Apply to:** `13-SCOPE-BOUNDARY.md`'s fixture subsections — both the fresh Phase-13 capture diffs and the backward-cited Phase-11 numbers for the SC4 constants-derivation section (D-09/CONTEXT.md "Specific Ideas" section already supplies the exact values to reuse: `maxAbsDelta ≈ 1.043081283569336e-07`, `maxRelDelta ≈ 7.269731577252969e-05`, `maxUlpDistance = 768`).

### Processor-level vs. manifest-level hash distinction
**Source:** `SuperGenius/SGProcessingManager/src/processingbase/ProcessingManager.cpp:1500-1510` (`ComputeManifestHash`/`output.combinedHash` assembly) and `SuperGenius/SGProcessingManager/include/capability/capability_types.hpp` (`CapabilitySnapshot::identityHash`/`executorIdentity`)
**Apply to:** Every place in `13-SCOPE-BOUNDARY.md`, `REQUIREMENTS.md` VALD-01, and `ROADMAP.md` SC1 that mentions "hash matching" — must consistently say processor-level `ProcessingResult` result/chunk hash, not `combinedHash`/`manifestHash`, per D-03.

## No Analog Found

None — all three artifacts (new doc, REQUIREMENTS.md edit, ROADMAP.md edit) have exact structural analogs from Phase 11's own equivalent deliverables.

## Metadata

**Analog search scope:** `.planning/workstreams/sgproc-render/phases/11-empirical-cross-machine-capture-run/`, `.planning/workstreams/sgproc-render/REQUIREMENTS.md`, `.planning/workstreams/sgproc-render/ROADMAP.md`, `SuperGenius/SGProcessingManager/src/processingbase/ProcessingManager.cpp`
**Files scanned:** 5 (11-CONTEXT.md, 11-CAPTURE-RESULTS.md, 11-01-PLAN.md, REQUIREMENTS.md excerpt, ROADMAP.md excerpt, ProcessingManager.cpp excerpt)
**Pattern extraction date:** 2026-08-12
