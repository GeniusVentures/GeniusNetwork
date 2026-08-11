# Phase 11: Empirical Cross-Machine Capture Run - Pattern Map

**Mapped:** 2026-08-11
**Files analyzed:** 4 (1 new doc, 2 edited docs, 1 file-move operation)
**Analogs found:** 2 / 4 (doc-structure analogs found for the results doc; the ROADMAP/REQUIREMENTS edits are literal before/after text substitutions with no "pattern" per se; the file-move has no code analog)

This phase is explicitly a documentation/data-organization phase. No `SGProcessingManager` source files are created or modified. Accordingly this pattern map is entirely about doc structure and exact text spans to edit, not code idioms.

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `11-CAPTURE-RESULTS.md` (new) | doc / results-report | transform (raw JSON → cited prose/tables) | `10-VERIFICATION.md` (structure/tone), `10-CONTEXT.md` D-08 (required content list) | role-match (doc-to-doc, not code) |
| `.planning/workstreams/sgproc-render/ROADMAP.md` (edit) | config/doc | transform (text substitution) | itself — exact current text block identified below | exact (literal string target, no analog needed) |
| `.planning/workstreams/sgproc-render/REQUIREMENTS.md` (edit) | config/doc | transform (text substitution) | itself — exact current text block identified below | exact (literal string target, no analog needed) |
| `caps/*` → `captures/*` (file move, 6 of 7 files) | none (data relocation) | file-I/O (move/delete) | none — no code analog applies | no analog needed |

## Pattern Assignments

### `11-CAPTURE-RESULTS.md` (new doc)

**Analog:** `.planning/workstreams/sgproc-render/phases/10-capture-harness-diff-tool-quantization-stub/10-VERIFICATION.md` (structure/tone reference) and CONTEXT.md D-08 (mandatory content checklist).

**Structure pattern observed in `10-VERIFICATION.md`** (a prior phase's numbers-citing doc in this same workstream):
- Opens with a frontmatter-style header block (phase, verified date, status) — optional for this doc since it isn't a verification report, but the convention of a short metadata header at top is consistent across this workstream's phase docs.
- Uses a `| # | Truth | Status | Evidence |`-style table to pin each claim to concrete evidence (file/line, live-run output, or JSON field values) rather than paraphrasing. E.g. line 36: `` `contentHashMatch: true`, `combinedHashMatch: true`, ... `maxAbsDelta: 0`, `maxRelDelta: 0`, `maxUlpDistance: 0`, `percentExceedingThreshold: 0%` ``  — cites JSON fields verbatim by name and value. `11-CAPTURE-RESULTS.md` should do the same for the two real diff JSONs (see exact values below).
- Explicitly separates "what's proven" from caveats/exclusions (10-VERIFICATION.md's `human_verification` frontmatter block calling out unverified branches). `11-CAPTURE-RESULTS.md` should analogously carry its own caveat section: the 2-machine scope decision (D-01) and the dropped-WSL rationale (D-04) — do not bury these in a footnote; per D-08 they are required content, not optional color.

**Required content checklist (from CONTEXT.md D-08 — this is authoritative, not the VERIFICATION.md structure):**
1. Cite exact numbers from `caps/diff-mnn-float.json` and `caps/diff-render.json`: `maxAbsDelta`, `maxRelDelta`, `maxUlpDistance`, `percentExceedingThreshold`, and hash-match booleans (`chunkHashesMatch`, `combinedHashMatch`, `contentHashMatch`).
2. State the 2-machine scope decision (D-01).
3. State the dropped-WSL rationale (D-04).
4. Use the exact machine labels already present in the `.cap` filenames for traceability: `Fuus-Mac-mini.local---macOS` and `Mofu---Windows` (per CONTEXT.md `<specifics>`).

**Actual source numbers to cite** (read directly from the two diff JSONs at repo-root `caps/`, verified during this pattern-mapping pass):

`caps/diff-mnn-float.json` (Mac vs Windows, MNN float32 fixture, 512 elements):
```json
{
  "chunkHashesMatch": [false, false, false, false, false, false, false, false, false, false, false, false, false, false, false],
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
```
(15 chunk hashes, all mismatched — consistent with quantization still being a no-op stub per Phase 10/11 scope.)

`caps/diff-render.json` (Mac vs Windows, render fixture, 256 elements, uint8):
```json
{
  "chunkHashesMatch": [],
  "combinedHashMatch": false,
  "contentHashMatch": true,
  "elementCount": 256,
  "elementType": "uint8",
  "maxAbsDelta": 0.0,
  "maxRelDelta": 0.0,
  "maxUlpDistance": 0,
  "percentExceedingThreshold": 0.0,
  "sizeMismatch": false
}
```
Note the render result: `contentHashMatch: true` (raw content bytes matched byte-for-byte across Mac/Windows) but `combinedHashMatch: false` — worth calling out explicitly in the results doc as a nuance (byte-identical content but the combined-hash-inclusive comparison still reports false; likely due to how `capture_diff` folds machine-identity/metadata into the combined-hash check versus the pure content hash — the results doc should state the numbers as observed, not editorialize on Phase 12 causes it doesn't need to resolve).

**No code pattern applies** to this file — it is a data-citing markdown document, not source code. The "pattern" here is strictly the doc-structure and required-content conventions above.

---

### `.planning/workstreams/sgproc-render/ROADMAP.md` — Phase 11 Success Criterion 1 edit

**Exact current text (line 90, under "### Phase 11: Empirical Cross-Machine Capture Run" → Success Criteria):**
```
  1. `capture_harness` has been run against Phase 09's render fixture and its MNN fixture on at least 3 distinct physical machines, including the user's Mac and PC, producing one capture file per machine per fixture.
```

Per CONTEXT.md D-03, this needs to change "at least 3 distinct physical machines" → "at least 2 distinct physical machines" plus the D-04 software-rasterizer caveat. Suggested target text (planner/executor should finalize exact wording, but the substitution target is this exact line):
```
  1. `capture_harness` has been run against Phase 09's render fixture and its MNN fixture on at least 2 distinct physical machines, including the user's Mac and PC, producing one capture file per machine per fixture. (A third machine's only available Vulkan device was a software rasterizer — excluded project-wide by `RenderProcessor::IsAcceptable()`'s existing device-type gate — so the dataset stays 2-machine; see Phase 11's captured-results doc for rationale.)
```

Also note the **Phase 11 Goal line** (line 85) itself still says "Mac + PC + a third" — CONTEXT.md D-03 only mandates SC1 be updated, but the goal-line wording will read inconsistently if left untouched. Flag this for planner discretion (not explicitly in-scope per D-03's literal text, but worth a one-line consistency edit in the same pass): current text is:
```
**Goal**: Real cross-hardware divergence statistics exist across the user's own machines (Mac + PC + a third), gathered using Phase 10's tooling with quantization still a no-op — this is a hands-on data-gathering step the whole milestone's precision decision depends on, not a coding or research activity, and it is deliberately kept as its own phase rather than folded into Phase 10 or Phase 12 per the milestone's confirmed hard dependency order.
```

---

### `.planning/workstreams/sgproc-render/REQUIREMENTS.md` — QUANT-04 edit

**Exact current text (line 27):**
```
- [ ] **QUANT-04**: Normalization parameters are fixed constants derived from CAPT/DIFF's empirical ≥3-machine data — not guessed a priori, not schema-configurable this milestone
```

Per CONTEXT.md D-03, change "≥3-machine data" → "≥2-machine data" plus caveat. Suggested target text:
```
- [ ] **QUANT-04**: Normalization parameters are fixed constants derived from CAPT/DIFF's empirical ≥2-machine data (Mac + Windows; a third machine's only available device was a software rasterizer, excluded per Phase 11's scope decision) — not guessed a priori, not schema-configurable this milestone
```

Also note the **Phase 11 mapping note at the bottom of REQUIREMENTS.md** (line 84) says "run Phase 10's tooling on ≥3 real machines" — same consistency concern as the ROADMAP goal line above; current text:
```
**Note:** Phase 11 (Empirical Cross-Machine Capture Run) covers no requirement directly — it is a hands-on data-gathering checkpoint (run Phase 10's tooling on ≥3 real machines) that produces the empirical input Phase 12's QUANT-04 depends on. See ROADMAP.md Phase 11 for detail.
```
CONTEXT.md D-03 names only ROADMAP SC1 and REQUIREMENTS QUANT-04 explicitly as in-scope edits — this note-line and the Phase-13/VALD-01 "≥3 different machines" wording elsewhere in both files are NOT named in D-03 and should be left alone unless the planner decides otherwise (flagging as a scope boundary, not a silent inconsistency to fix under this ticket).

---

### `caps/` → `captures/` file relocation

**No code analog needed or applicable** — this is a plain file move/delete, not a source-code change. Confirmed current repo-root `caps/` listing (as of this pattern-mapping pass):
```
caps/diff-mnn-float.json
caps/diff-render.json
caps/xhw-mnn-float_Fuus-Mac-mini.local---macOS_20260811T212907.cap
caps/xhw-mnn-float_Mofu---Linux_20260811T230448.cap        <- DROP per D-04 (WSL/llvmpipe, not carried into captures/)
caps/xhw-mnn-float_Mofu---Windows_20260811T212812.cap
caps/xhw-render_Fuus-Mac-mini.local---macOS_20260811T213105.cap
caps/xhw-render_Mofu---Windows_20260811T213052.cap
```
Per CONTEXT.md D-09: move the 6 non-WSL files (2 diff JSONs + 4 `.cap` files) into `.planning/workstreams/sgproc-render/phases/11-empirical-cross-machine-capture-run/captures/`, then delete the now-empty repo-root `caps/` directory. The WSL `.cap` file (`xhw-mnn-float_Mofu---Linux_20260811T230448.cap`) must NOT appear in the destination — CONTEXT.md leaves its disposition (delete vs. archive untracked) to executor discretion, only requiring it not land in `captures/` or the results doc.

## Shared Patterns

None apply in the code sense (auth/error-handling/etc. are not relevant — no source touched). The one cross-cutting convention worth calling out: **all three doc edits (ROADMAP SC1, REQUIREMENTS QUANT-04, and the new results doc) must use the same "≥2 distinct physical machines, Mac + Windows, third-machine software-rasterizer excluded" phrasing** so a future reader of any one of the three documents gets a consistent story without needing to cross-reference CONTEXT.md's D-01/D-03/D-04.

## No Analog Found

| File | Role | Data Flow | Reason |
|---|---|---|---|
| `caps/` → `captures/` move | none | file-I/O | Pure filesystem relocation; no code pattern exists or is needed for a file move/delete |

## Metadata

**Analog search scope:** `.planning/workstreams/sgproc-render/` (ROADMAP.md, REQUIREMENTS.md, phase 10's doc set), repo-root `caps/` directory listing
**Files scanned:** `10-CONTEXT.md`, `10-VERIFICATION.md`, `ROADMAP.md`, `REQUIREMENTS.md`, `caps/diff-mnn-float.json`, `caps/diff-render.json`, repo-root `caps/` file listing
**Pattern extraction date:** 2026-08-11
