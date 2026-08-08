# Phase 10: Capture Harness & Diff Tool (Quantization Stub) - Context

**Gathered:** 2026-08-08
**Status:** Ready for planning

<domain>
## Phase Boundary

Developer tooling exists to capture, on any single machine, per-run raw output values, per-chunk hashes, and the combined hash from Phase 09's existing render + MNN fixtures, and to diff two or more such capture files with quantitative divergence stats — with quantization wired in as a no-op/identity stub so the full invasive plumbing (14 processor files + one new `ExecutionContext` field) is exercised and proven end-to-end once, without yet claiming a real cross-hardware precision. This is `tools/capture/` CLI tooling (`capture_harness`, `capture_diff`), not a CTest-gated correctness suite — a meaningful cross-machine pass/fail requires physical access to ≥2 machines, which is Phase 11's job.

**Depends on:** Nothing (continues from v2.0 Phase 09; first phase of v2.1).

**Requirements covered:** CAPT-01, CAPT-02, CAPT-03, DIFF-01, DIFF-02, DIFF-03.

</domain>

<decisions>
## Implementation Decisions

### Capture File Format & Naming

- **D-01:** Binary capture file format, reusing the existing `SerializeArtifact`/`SerializeManifest` deterministic binary convention from Phase 08's `artifact_serializer.hpp`/`.cpp`, with a new raw-bytes section appended for the per-element raw output dump. Matches research's explicit recommendation — avoids inventing a second serialization convention alongside the one that already exists.
- **D-02:** Capture file naming encodes fixture, machine, and timestamp (e.g. `render-happy-path_MacBook-Pro-M2_20260807T143000.cap`) — sortable by time, and immediately shows which fixture and machine produced it. This matters because Phase 11 involves manually copying capture files between the user's own machines; timestamped names prevent accidental overwrites and mix-ups.

### Machine-Identity Tag Content (CAPT-01)

- **D-03:** The machine-identity tag records hostname + OS only (e.g. `MacBook-Pro-M2 / macOS 15.1`) — not GPU vendor/driver info. Simpler to gather at capture time; still uniquely identifies which of the user's machines produced a given capture.

### Same-Node Stability Check Workflow (CAPT-03)

- **D-04:** `capture_harness` gets a built-in `--repeat N` flag. It runs the fixture N times internally and self-checks that all N runs' combined and chunk hashes match, rather than requiring the user to manually run it twice and diff the results with `capture_diff`. One command satisfies CAPT-03 directly.
- **D-05:** If `--repeat N` finds any instability (hashes differ across the N runs), `capture_harness` aborts and writes no capture file at all — it must not silently produce a capture file that later gets used for cross-machine comparison without the stability guarantee CAPT-03 requires.

### Diff Tool Output Format (DIFF-01, DIFF-02, DIFF-03)

- **D-06:** `capture_diff` emits both a human-readable console summary AND a machine-readable JSON report (via e.g. a `--json` flag or always alongside console output) in Phase 10 itself — not deferred to a later phase. Anticipates Phase 11's need to script/compare across multiple machine pairs (Mac vs. PC, Mac vs. third, PC vs. third).
- **D-07:** DIFF-02's "percentage of elements exceeding a threshold" uses a fixed default threshold value, not a CLI-configurable flag, for this phase.

### Claude's Discretion

- The exact fixed default threshold value for DIFF-02 (percentage-of-elements-exceeding-threshold) — the user explicitly deferred this number to Claude's judgment. Since quantization is a no-op/identity stub this phase (no real cross-hardware tolerance claim yet), pick a small, clearly-documented epsilon; it exists to exercise the reporting mechanism, not to make a precision claim. Phase 12 will revisit this once real empirical data exists.
- Exact `--repeat` default N (research/roadmap says N≥2; a sensible default like 2 or 3 is fine unless a specific value is needed for the smoke test).
- Exact JSON schema/field names for `capture_diff`'s machine-readable report.
- Exact CLI flag names and argument parsing approach for `capture_harness`/`capture_diff` (follow existing SGProcessingManager tool/test CLI conventions if any exist; otherwise a simple flag parser is fine — no new dependency).
- Internal structure of the shared quantization stub (function signatures, where the no-op utility lives) — research already specifies this at the file:line level (`sgprocmanagerquant`, ~20 insertion points across 14 processor files); Phase 10 wires these calls in as identity/pass-through, Phase 12 replaces the internals only.
- Whether the raw-bytes section appended to the binary capture format needs its own versioning/magic-number scheme, following whatever convention `artifact_serializer.hpp` already uses for forward-compatibility.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements & Roadmap
- `.planning/workstreams/sgproc-render/REQUIREMENTS.md` — CAPT-01/02/03, DIFF-01/02/03 locked requirements for this phase
- `.planning/workstreams/sgproc-render/ROADMAP.md` (Phase 10 section) — goal, success criteria, dependency-order note (Phase 10→11→12→13 is a hard, non-reorderable dependency chain)

### Research (HIGH confidence, file:line-level architecture — no further research phase needed)
- `.planning/workstreams/sgproc-render/research/SUMMARY.md` — full research synthesis: recommended stack (`sgprocmanagerquant`), architecture (20 insertion points across 14 processor files), critical pitfalls (tolerance-vs-security tension, NaN/Inf/denormal canonicalization, quantizing only the visible hash site), and the explicit Phase 1(=10)→2(=11)→3(=12)→4(=13) roadmap rationale
- `.planning/workstreams/sgproc-render/research/ARCHITECTURE.md`, `STACK.md`, `FEATURES.md`, `PITFALLS.md` — component-level detail backing SUMMARY.md

### Prior Phase Context (v2.0 Phases 06-09)
- `.planning/workstreams/sgproc-render/phases/09-processor-pass-graph-conformance-suites/09-CONTEXT.md` — D-07 (conformance contract: `StartProcessing()` + `ExecutionContext`, deterministic output hash), D-05 (`GTEST_SKIP()` + Vulkan device probe pattern for GPU-dependent tests)
- `.planning/workstreams/sgproc-render/phases/08-structured-artifacts-execution-manifests/08-CONTEXT.md` — D-07 (SHA-256 everywhere), D-04 (custom deterministic binary serialization — the exact convention D-01 above reuses)
- `.planning/workstreams/sgproc-render/phases/07-cancellable-execution-context/07-CONTEXT.md` — D-10/D-11 (progress event shape and stages) — relevant since `ExecutionContext` gets a new capture-callback field following the same no-op-by-default pattern as `progressCallback`

### Existing Code (Source of Truth)
- `SuperGenius/SGProcessingManager/include/util/sha256.hpp` / `src/util/sha256.cpp` — the unmodified `sgprocmanagersha::sha256()` function; quantization/capture hooks sit immediately before its call sites, never inside it
- `SuperGenius/SGProcessingManager/include/execution/execution_context.hpp` — `ExecutionContext` struct; gets one new optional capture-callback field mirroring the existing `progressCallback` no-op pattern (see `ExecutionContext::NoOp()`)
- `SuperGenius/SGProcessingManager/include/artifacts/artifact_serializer.hpp` / `src/artifacts/artifact_serializer.cpp` — `SerializeArtifact`/`SerializeManifest`, the binary format D-01 extends with a new raw-bytes section
- `SuperGenius/SGProcessingManager/src/processors/processing_processor_render.cpp:2156` — example combined-hash call site (`sgns::sgprocmanagersha::sha256(readbackBytes.data(), readbackBytes.size())`)
- `SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_float.cpp:307,330` — example MNN chunk-hash and stitched/combined-hash call sites, showing the per-chunk-then-combined two-layer pattern research describes

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`artifact_serializer.hpp`/`.cpp`** (Phase 08) — deterministic binary serialization convention; capture files extend this rather than inventing a new format (D-01).
- **`sgprocmanagersha::sha256()`** — stays completely unmodified; capture/quantization hooks are pre-processing steps inserted before its existing call sites.
- **`ExecutionContext::NoOp()` pattern** (Phase 07) — the established way to add a new opt-in callback field (like `progressCallback`) that defaults to a no-op; the new raw-output-capture field follows this same shape.
- **Phase 09's existing render + MNN fixtures** — this phase captures and diffs against them directly; no new fixtures are built.

### Established Patterns
- **Per-chunk-then-combined two-layer hashing** — every MNN processor computes a chunk hash per output element/chunk, then a separate combined/stitched hash over the assembled output (e.g. `processing_processor_mnn_float.cpp:307` then `:330`). The capture harness must record bytes at both layers, matching how Phase 12's quantization will eventually need to cover both layers too.
- **GPU-dependent test skip pattern** (Phase 09 D-05) — if the capture harness's render-fixture path needs a Vulkan device probe (it runs the real render pipeline), the existing `GTEST_SKIP()`-equivalent pattern applies to the thin smoke test, though `capture_harness` itself is a standalone CLI tool, not a CTest target.

### Integration Points
- **14 processor files** (13 MNN + RenderProcessor) — each needs the new capture-callback wired in immediately before its existing `sha256()` call site(s), per research's ~20-insertion-point enumeration.
- **`ExecutionContext`** — the single new field threading the opt-in raw-output-capture callback through `ProcessingManager::Process()` into every processor, without touching the stable 6-argument `StartProcessing()` virtual interface.
- **`tools/capture/`** (new top-level directory, not under `test/`) — houses `capture_harness.cpp` and `capture_diff.cpp` as standalone CLI executables, per research's explicit placement recommendation (a meaningful pass/fail needs ≥2 physical machines, which CTest can't express).

</code_context>

<specifics>
## Specific Ideas

- This tooling is used by the user personally, by hand, across their own Mac + PC + a third machine in Phase 11 — CLI ergonomics and file-naming discipline matter more than they would for an automated CI-only tool, which is why file naming (D-02) and the built-in `--repeat` stability check (D-04) were prioritized for discussion.
- Quantization in this phase is strictly a no-op/identity stub — the goal is proving the full plumbing (14 files + `ExecutionContext` field) works end-to-end once, not making any cross-hardware precision claim yet. That claim only becomes meaningful in Phase 12 after Phase 11's empirical data exists.

</specifics>

<deferred>
## Deferred Ideas

- **Real quantization/normalization logic** — explicitly out of scope for Phase 10 (stub only); belongs to Phase 12 per the roadmap's hard dependency order.
- **CLI-configurable DIFF-02 threshold** — user chose a fixed default for this phase; a `--threshold` flag could be added later if Phase 11's real data shows the fixed default doesn't fit.
- **GPU vendor/driver detail in the machine-identity tag** — user chose hostname + OS only; can be added later if diagnosing a specific divergence in Phase 11/12 turns out to need it.

No scope-creep items came up during discussion — all deferrals above are precision/detail refinements within Phase 10's own topics, not new capabilities.

</deferred>

---

*Phase: 10-Capture Harness & Diff Tool (Quantization Stub)*
*Context gathered: 2026-08-08*
