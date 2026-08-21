# Phase 19: Validation Re-Verification - Context

**Gathered:** 2026-08-21
**Status:** Ready for planning

<domain>
## Phase Boundary

Determine, with real evidence rather than assumption, whether Phase 15's `ProcessingValidationCore::ValidateResults` tolerance-fallback mechanism actually closes VALD-01's original MNN float32 gap (Phase 13's chunk-hash-mismatch finding, narrowed by Phase 13's own gap-closure round to 1/15 chunks at the current S=2^15 quantization scale) — and document the outcome honestly (closed / partially closed / still open), whichever way it lands.

This is a re-verification phase, not a fix phase: it exercises an already-shipped mechanism (Phase 15, v2.2) against an already-characterized fixture (Phase 13, v2.1). No new capability is being added.

</domain>

<decisions>
## Implementation Decisions

### Fixture data source
- **D-01 (SUPERSEDED 2026-08-21 — see D-01-REVISED below):** Reuse Phase 13's existing S=2^15-round captures — do not run a new hands-on 2-machine capture session. The exact pair to use is `xhw-mnn-float_Fuus-Mac-mini.local---macOS_20260812T232347.cap` (Mac) vs `xhw-mnn-float_Mofu---Windows_20260812T232430.cap` (Windows), both under `.planning/workstreams/sgproc-render/phases/13-re-validation-scope-boundary-documentation/captures/`. This is the exact pair behind Phase 13's "SC1 Refit" finding (1/15 chunks divergent, chunk 10, `maxAbsDelta = 3.0517578125e-05` — exactly one S=2^15 grid step). Precedent: Phase 17-09 already established that reusing already-captured data (rather than a fresh hardware round) is acceptable when it already answers the question at hand.

- **D-01-REVISED:** During Phase 19 execution, the exact fixture pair named above was found to be **unreadable by any current tooling** — `sgns::sgproccapture::DeserializeCaptureFile()` returns `false` for both halves, independently reproduced with the unmodified `capture_diff` CLI (the same tool that produced Phase 13's own published numbers). Root cause: `SGProcessingManager` commit `bf7e694` ("fix(17): read MANIFEST_V2_SERIALIZED_SIZE in DeserializeCaptureFile, not the stale pre-ARTF-10 constant", 2026-08-19) made the parser unconditionally require the newer post-Phase-16 manifest format, silently breaking backward-compatibility with every pre-Phase-16 `.cap` file (all of Phase 13's captures included). Presented to the user as a 3-way decision (document-as-still-open / fix the parser / fresh capture); user chose **fresh 2-machine capture** — re-run the MNN float32 fixture live on the same two machines (Mac `Fuus-Mac-mini.local`, Windows `Mofu`) using the current `capture_harness` tool, producing new-format `.cap` files that parse cleanly under current tooling. This explicitly reverses D-01's "no new hands-on capture session" constraint. D-02 through D-04 are unaffected — the harness style, all-15-chunks coverage, and no-production-fix scope boundary all still apply, just against freshly captured bytes instead of Phase 13's archived ones.

### Test harness style
- **D-02:** Feed the captured Mac/Windows chunk bytes into `ValidateResults`/`AttemptToleranceFallback` via a **direct unit-level call** — construct `ChunkContribution` structs directly from the captured bytes/hashes, mirroring `processing_validation_core_test.cpp`'s existing `ProcessingValidationCoreTest` style (SC1-SC4's own proof style in Phase 15's verification). Explicitly **not** the heavier SECV-02 full-pipeline style (real `ProcessTaskSplitter::SplitTask` + `SubTaskQueueAccessorImpl`) — that pattern remains available as a fallback if the direct-call approach turns out to be structurally insufficient to prove SC1's "not a re-derived or substitute fixture" bar, but the direct-call route is preferred to start.
- This exercises the exact same production tolerance-fallback code path unchanged since Phase 15 shipped (`processing_validation_core.cpp` lines 63-146, 257-355).

### Chunk coverage
- **D-03:** Exercise **all 15 chunks** of the fixture through `ValidateResults`, not just chunk 10. Matches ROADMAP SC2's literal wording ("which chunks match/mismatch post-fallback"), and mirrors how `ValidateResults` actually runs in production — over every chunk of a subtask, not a single cherry-picked one. The other 14 chunks are expected to already match bit-for-bit per `13-SCOPE-BOUNDARY.md`'s own SC1 Refit data, so covering all 15 is expected to cost a loop/iteration in the harness, not new investigation.

### Still-open scope boundary
- **D-04:** If the re-run shows chunk 10 (or any chunk) is **still not within tolerance**, the phase stops at honest documentation only — no fix is attempted. This matches ROADMAP SC3's own framing ("documented as explicitly closed, partially closed, or still open... any remaining gap characterized rather than left implicit") and the phase's name ("Re-Verification", not "Fix"). Any further tuning of the S=2^15 quantization scale would re-litigate a decision Phase 13 already closed with a documented tradeoff (S=2^15 was chosen specifically to keep one power-of-two step of margin above a confirmed SECV-01 failure boundary at S=2^14 — see `quantization.hpp` lines 78-102). A narrow exception: if the re-run surfaces a bug in the *test harness itself* (not the production tolerance logic), fixing the harness bug is in scope — only production-logic changes (quantScale, `IsFloatChunkWithinTolerance`'s bound, etc.) are out of scope this phase.

### Claude's Discretion
- Exact harness file location/naming (e.g. a new `TEST_F` in `processing_validation_core_test.cpp` vs. a small dedicated re-verification tool) — follow whichever existing convention (`processing_validation_core_test.cpp` vs. a `capture_diff`-adjacent tool) proves simplest given D-02's direct-call approach.
- How to parse the `.cap` files' raw per-chunk bytes into the `ChunkContribution` structs `ValidateResults` expects — read `capture_file_format.hpp`'s documented `rawRecordsPerArtifact` layout (already used by `capture_diff.cpp` and `capture_harness.cpp`'s `SelfCheckCapturedBytes`) to do this correctly.
- Exact output document naming/format for the outcome (see Canonical References below for the established convention to follow).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Original VALD-01 gap characterization (fixture + measurements)
- `.planning/workstreams/sgproc-render/phases/13-re-validation-scope-boundary-documentation/13-SCOPE-BOUNDARY.md` — the authoritative source for the exact fixture, chunk 10's measured divergence (`maxAbsDelta = 3.0517578125e-05`, `maxUlpDistance = 2048`), and the S=2^15 derivation/tradeoff history. Read the "SC1 Refit" and "SC1 Diagnostic: Chunk 10" sections specifically.
- `.planning/workstreams/sgproc-render/phases/13-re-validation-scope-boundary-documentation/captures/` — contains the actual `.cap` files, including the exact pair D-01 specifies (`xhw-mnn-float_Fuus-Mac-mini.local---macOS_20260812T232347.cap`, `xhw-mnn-float_Mofu---Windows_20260812T232430.cap`) and the corresponding `diff-mnn-float-refit.json`/`diff-mnn-float-refit-chunkdiag.json` (pre-computed reference values to cross-check the new harness against).

### Production tolerance-fallback mechanism (what's being re-verified)
- `SuperGenius/SGProcessingManager/include/util/diff_utils.hpp` — `IsFloatChunkWithinTolerance`'s D-03 bound derivation (`2/S`, two grid steps of margin) — this is the exact number chunk 10's measured delta (`1/S`) will be compared against.
- `SuperGenius/SGProcessingManager/include/util/quantization.hpp` — current S=2^15 (32768.0f) fallback constant and its full derivation/tradeoff history (lines 78-120), cited directly by D-04 above.
- `SuperGenius/src/processing/processing_validation_core.hpp`/`.cpp` — `ValidateResults`, `ChunkContribution`, `AttemptToleranceFallback` (lines 257-355) — the exact production code path this phase re-runs the fixture through.
- `SuperGenius/test/src/processing/processing_validation_core_test.cpp` — the existing `ProcessingValidationCoreTest` cases (SC1-SC4 style), the pattern D-02 says to mirror.
- `.planning/workstreams/sgproc-render/phases/15-validation-comparison-mechanism/15-VERIFICATION.md` — confirms this mechanism is unchanged/shipped and documents exactly what proof style Phase 15 itself considered sufficient (Truths 3/4 use the same direct-unit-test style D-02 selects).

### Capture file parsing
- `SuperGenius/SGProcessingManager/tools/capture/capture_file_format.hpp` — `CaptureRecord`/`rawRecordsPerArtifact` layout; needed to correctly extract chunk 10's (and the other 14 chunks') raw bytes from the `.cap` files.

### Prior-round precedent for reusing captured data + honest-outcome documentation convention
- `.planning/workstreams/sgproc-render/phases/17-render-path-cross-hardware-tolerance/17-TOLERANCE-RESULTS.md` (Gap Closure Addendum) and `17-09-SUMMARY.md` — precedent for reusing already-captured Round 2 data instead of a new hardware round, and for wiring an existing production tolerance function (`IsByteChunkWithinTolerance`) into an offline/test-time check without changing production code.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `processing_validation_core_test.cpp`'s existing `ProcessingValidationCoreTest` fixture/test scaffolding — the harness for this phase's new test(s) should extend this file rather than create a new binary.
- `sgprocmanagerdiff`'s `IsFloatChunkWithinTolerance`/`ComputeFloat32Diff` — already shared between `capture_diff` (offline tool) and `ValidateResults` (production), so no new comparison logic needs to be written.
- The pre-computed `diff-mnn-float-refit.json`/`diff-mnn-float-refit-chunkdiag.json` in Phase 13's captures dir — useful as an independent cross-check that the new harness parses the same `.cap` files correctly (its own numbers should match capture_diff's already-published ones before drawing any new conclusion from `ValidateResults`'s behavior).

### Established Patterns
- "Direct unit-level ChunkContribution construction from real captured bytes, call the production function directly" is a new pattern for this phase, but it's a natural extension of Phase 15's existing `ProcessingValidationCoreTest` cases (which used synthetic/hand-built chunk data, not real cross-machine captures).
- Honest-outcome-reporting convention: `13-SCOPE-BOUNDARY.md` and `17-09`'s gap-closure summary both state results plainly (including "gap persists but narrowed" framing) rather than rounding partial results into a pass — Phase 19's own outcome doc should follow this same convention per D-04/ROADMAP SC3.

### Integration Points
- No production code is expected to change (per D-04) unless a harness-only bug is found. The new test/harness integrates purely at the test layer — `processing_validation_core_test.cpp` (or an adjacent small tool) reading `.cap` files and calling already-shipped `ValidateResults`/`AttemptToleranceFallback`.

</code_context>

<specifics>
## Specific Ideas

No specific UI/UX ideas (this is a backend validation/test-harness phase). The core "specific idea" is the exact fixture pair named in D-01 — the user confirmed reusing that exact pre-existing data rather than capturing anything new.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope. The "if still open, should we fix it" question (D-04) was raised and explicitly resolved as document-only for this phase; any future fix (should the gap turn out to still be open) is deferred to a future phase, consistent with VALD-01's already-accepted override precedent at v2.1 close.

</deferred>

---

*Phase: 19-Validation Re-Verification*
*Context gathered: 2026-08-21*
