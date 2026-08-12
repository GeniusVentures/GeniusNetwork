# Phase 13: Re-Validation & Scope Boundary Documentation - Context

**Gathered:** 2026-08-12
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 13 is a re-validation + documentation phase, not a coding phase (mirrors Phase 11's nature). It: (1) re-runs `capture_harness`/`capture_diff` on the user's Mac + Windows machines with Phase 12's real quantization active (not Phase 10/11's no-op stub), confirming the processor-level result/chunk hash now matches cross-machine; (2) re-runs the existing SECV-01 counter-test (`secv01_counter_test.cpp`) and cites the pass; (3) writes a single combined scope-boundary + results document. Two roadmap/requirements wording corrections (machine count, hash target) are locked decisions for the planner to apply as doc-edit tasks — same class of fix Phase 11 already made to its own success criteria.

No new production code is planned. No new SECV-01 test logic is planned — Phase 12's constants are the final precision.

</domain>

<decisions>
## Implementation Decisions

### Machine-count reconciliation (VALD-01 / ROADMAP SC1)
- **D-01:** No genuine 3rd physical machine has appeared since Phase 11. Phase 13 accepts the same 2-machine dataset (Mac + Windows) that Phase 11 established — mirrors Phase 11's own D-01/D-03 precedent exactly.
- **D-02:** REQUIREMENTS.md's VALD-01 text and ROADMAP.md's Phase 13 SC1 text must be edited during planning/execution to read "≥2 distinct physical machines" (plus reference to the excluded software-rasterizer caveat, same framing Phase 11 used for QUANT-04/its own SC1). This is a locked decision — the planner turns it into a concrete doc-edit task, not something to re-discuss.

### Hash-target wording fix (VALD-01 / ROADMAP SC1)
- **D-03:** VALD-01/SC1's literal "matching combined hashes" is corrected to mean the **processor-level** `ProcessingResult.hash` and its per-chunk hashes (the hash `ProcessingValidationCore` actually compares for cross-node consensus) — NOT `ProcessOutput.combinedHash`/`ExecutionManifest.manifestHash`, which Phase 12's D-01/D-02 established bakes in machine-specific `executorIdentity`+`gpuMemoryUsedBytes` and can never match cross-machine by construction. Re-validation must capture/diff at the processor-level hash layer.
- **D-04:** REQUIREMENTS.md VALD-01 and ROADMAP.md Phase 13 SC1 wording get edited during this phase to explicitly say "processor-level result/chunk hash" instead of the ambiguous "combined hash" — same class of fix as D-02, applied together.

### Re-capture logistics
- **D-05:** Fresh `capture_harness` runs happen by hand on both machines (Mac + Windows) with binaries rebuilt against Phase 12's real quantization — same hands-on data-gathering pattern as Phase 11 (its D-01/D-07). Claude cannot reach the user's Mac directly; the user runs it personally on both machines and hands back the resulting `.cap` files.
- **D-06:** Fresh capture files and `capture_diff` JSON reports land in a new `captures/` subdirectory inside Phase 13's own phase directory (`.planning/workstreams/sgproc-render/phases/13-re-validation-scope-boundary-documentation/captures/`) — NOT appended into Phase 11's existing `captures/` dir. Keeps stub-era (Phase 11) and real-quantization-era (Phase 13) evidence unambiguously separated by directory, not just filename/timestamp.
- **D-07:** "Re-run SECV-01 at the final precision" (ROADMAP SC2) means literally re-running the existing `secv01_counter_test.cpp` CTest target and citing the fresh pass result in the results doc — no new test code. Phase 12's constants ARE the final precision; nothing changes between Phase 12 and Phase 13 on the SECV-01 side.

### Scope-boundary doc
- **D-08:** The scope-boundary record (ROADMAP SC3) is a new phase-owned document, `13-SCOPE-BOUNDARY.md`, in this phase's directory — mirrors Phase 11's `11-CAPTURE-RESULTS.md` convention rather than folding into PROJECT.md.
- **D-09:** `13-SCOPE-BOUNDARY.md` is a single combined document covering: the explicit scope boundary (hash comparison is now cross-hardware tolerant; `ProcessingValidationCore::ValidateResults`'s concatenation bug remains unfixed; no cross-node consensus/redundant-execution plumbing was built — per REQUIREMENTS.md's Out of Scope table), the re-validation results (SC1 processor-level hash match across Mac+Windows, SC2 SECV-01 fresh-pass citation), and SC4's final normalization constants with their empirical derivation citing Phase 11's captured numbers (`maxAbsDelta ≈ 1.043e-07`, `maxRelDelta ≈ 7.27e-05`, `maxUlpDistance = 768` for MNN float32; byte-identical content hash for render uint8). Not split into separate boundary/results docs — Phase 13's scope is small enough that one file stays coherent.

### Claude's Discretion
- Exact prose/structure of `13-SCOPE-BOUNDARY.md` (tables vs. prose, section ordering) — the required content is D-09's list.
- Exact wording of the ROADMAP.md/REQUIREMENTS.md edits from D-02/D-04, as long as they land on "≥2 machines" and "processor-level result/chunk hash" respectively.
- Whether `.cap` filenames follow Phase 11's exact naming convention (`{fixture}_{machine}---{OS}_{timestamp}.cap`) — almost certainly yes, for consistency, but not a hard requirement.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements & Roadmap (need the D-02/D-04 wording edits applied)
- `.planning/workstreams/sgproc-render/REQUIREMENTS.md` — VALD-01 (needs "≥2 machines" + "processor-level result/chunk hash" wording per D-02/D-04); Out of Scope table (source of the scope-boundary language for D-09)
- `.planning/workstreams/sgproc-render/ROADMAP.md` (Phase 13 section) — goal, SC1-SC4 (SC1 needs the same two wording edits; SC3 is what `13-SCOPE-BOUNDARY.md` must satisfy)

### Prior Phase Context (source of the D-01/D-03/D-05 precedents this phase mirrors)
- `.planning/workstreams/sgproc-render/phases/11-empirical-cross-machine-capture-run/11-CONTEXT.md` — D-01/D-02/D-03 (2-machine scope decision + the exact wording-fix pattern this phase's D-02/D-04 replicate), D-07 (`--repeat` self-check), D-08/D-09 (results-doc + captures-dir convention this phase's D-06/D-08 replicate)
- `.planning/workstreams/sgproc-render/phases/11-empirical-cross-machine-capture-run/11-CAPTURE-RESULTS.md` — exact prior-phase captured numbers to cite in `13-SCOPE-BOUNDARY.md`'s SC4 constants-derivation section
- `.planning/workstreams/sgproc-render/phases/12-quantization-normalization-implementation/12-CONTEXT.md` — D-01 (processor-level hash vs. manifest hash distinction — the direct source of this phase's D-03), D-02 (explicitly flags Phase 13 must reconcile the "combined hash" wording — the task this phase's D-03/D-04 close out), D-10 through D-13 (SECV-01 mechanism/assertion shape, relevant to interpreting the D-07 re-run)

### Existing Code (Source of Truth — read, not modified, this phase)
- `SuperGenius/SGProcessingManager/include/util/quantization.hpp`, `src/util/quantization.cpp` — Phase 12's real normalization; the "final precision" D-07 refers to
- `SuperGenius/test/src/processing_conformance_security/secv01_counter_test.cpp` — the existing CTest target D-07 re-runs as-is
- `SuperGenius/SGProcessingManager/tools/capture/capture_harness.cpp`, `capture_diff.cpp`, `capture_file_format.hpp` — the CLI tools D-05 runs unmodified against the rebuilt binaries
- `SuperGenius/SGProcessingManager/src/processingbase/ProcessingManager.cpp:1500-1510` — where `ComputeManifestHash`/`ProcessOutput.combinedHash` is assembled (confirms D-03's "manifest hash, not processor-level hash" distinction)
- `SuperGenius/SGProcessingManager/include/capability/capability_types.hpp` — `CapabilitySnapshot::identityHash`/`executorIdentity`, confirms why the manifest-level hash is structurally machine-specific (backs D-03)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `capture_harness`/`capture_diff` CLI tools (Phase 10, unmodified since) — this phase only *runs* them against the Phase-12-rebuilt binaries, no new code
- `secv01_counter_test.cpp` (Phase 12) — this phase only *re-runs* it via CTest, no new test code
- Phase 11's `11-CAPTURE-RESULTS.md` structure — direct template for `13-SCOPE-BOUNDARY.md`'s results section

### Established Patterns
- Hands-on data-gathering via the user's own machines, results written to a phase-owned doc citing exact captured numbers (Phase 11's whole approach) — Phase 13 repeats this pattern one more time, now with real quantization active
- Roadmap/requirements wording corrections as a planned doc-edit task rather than pre-emptive rewording during roadmap creation (Phase 11's D-03 precedent) — Phase 13's D-02/D-04 are the second instance of this same pattern

### Integration Points
- None — this phase produces documentation and re-runs existing tooling/tests; it does not touch `SGProcessingManager` source

</code_context>

<specifics>
## Specific Ideas

- Machine labels for traceability, matching Phase 11's and Phase 12's convention: `Fuus-Mac-mini.local---macOS`, `Mofu---Windows`
- Concrete Phase 11 numbers to cite in `13-SCOPE-BOUNDARY.md`'s constants-derivation section: `maxAbsDelta ≈ 1.043081283569336e-07`, `maxRelDelta ≈ 7.269731577252969e-05`, `maxUlpDistance = 768` (MNN float32, 512 elements, Mac vs. Windows, pre-quantization); render uint8 fixture showed `contentHashMatch: true` pre-quantization already

</specifics>

<deferred>
## Deferred Ideas

- **Actually excluding `executorIdentity`/`gpuMemoryUsedBytes` from `ComputeManifestHash`** so `ProcessOutput.combinedHash` itself becomes cross-machine-comparable — considered and rejected in Phase 12 (its own deferred-ideas list), reaffirmed out of scope here by D-03. Would only matter if a future consumer (e.g. a provenance dashboard) needs the manifest-level hash to be cross-machine-comparable.
- **Adding a genuine 3rd physical machine's captures** — not blocking (D-01), same as Phase 11's own deferral; could be folded in later as a small follow-up to `13-SCOPE-BOUNDARY.md` without reopening this phase's scope decision.

### None further — discussion stayed within phase scope

</deferred>

---

*Phase: 13-Re-Validation & Scope Boundary Documentation*
*Context gathered: 2026-08-12*
