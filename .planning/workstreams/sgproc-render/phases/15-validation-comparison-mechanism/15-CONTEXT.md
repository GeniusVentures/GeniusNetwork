# Phase 15: Validation Comparison Mechanism - Context

**Gathered:** 2026-08-14
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 15 fixes `ProcessingValidationCore::ValidateResults`'s concatenation bug — today, when two subtasks process the same chunk, their chunk-hash bytes are concatenated (`chunks.insert(...).first->second.insert(end(), ...)`) instead of compared, so a genuine cross-node hash mismatch silently passes. The fix must actually diff same-chunk hashes across subtasks (XNODE-01b), then extend that comparison with a bounded numeric-tolerance fallback (XNODE-02): when hashes for the same chunk differ, fetch the underlying chunk data and run a numeric diff before declaring a genuine mismatch — reusing `capture_diff`'s per-chunk comparison technique (v2.1 Phase 13), not requiring bit-exact hash equality. A counter-test (SECV-02) proves the combined mechanism — hash-compare fix + tolerance fallback acting together — still catches a genuinely wrong/corrupted subtask result, mirroring SECV-01's methodology.

Scope is pairwise: all five ROADMAP success criteria are framed around two subtasks sharing one chunk. Actual cross-node consensus/redundant-execution orchestration plumbing (deciding which subtasks get assigned the same chunk, trust scoring, N-way voting) is `XNODE-01c` — explicitly out of scope for v2.2, deferred to a future milestone. This phase makes the comparison mechanism itself correct and tolerant; it does not build or touch the orchestration that produces redundant same-chunk assignments in the first place.

Depends on Phase 14 (shipped 2026-08-14): the numeric-tolerance fallback derives its threshold from Phase 14's schema-configurable `quantScale`/`byteQuantMode`, so Phase 14's resolver infrastructure (`ResolveQuantScale`/`ResolveByteQuantMode`) must exist first.

</domain>

<decisions>
## Implementation Decisions

### Data source for the numeric-tolerance fallback (XNODE-02)
- **D-01:** On a chunk-hash mismatch, fetch both subtasks' underlying output data via the **existing** `ipfs_results_data_id`/output-URI mechanism — the same `FileManager`-based path `ProcessingManager::Process()` already uses to save (and IPFS-dual-cache) subtask output (`ProcessingManager.cpp:1585-1618`, keyed by each output's declared `source_uri_param` in the job schema JSON). **No new fetch mechanism, no `SGProcessing.proto` changes.** Rejected: extending `SubTaskResult` to carry raw chunk bytes inline (proto/wire-format change) — the existing IPFS-backed path already gets the data there.
- **D-02:** This is a mismatch-path-only fetch — no I/O added to the trivial matching-hash case. `ValidateResults`/its caller (`SubTaskQueueAccessorImpl::FinalizeQueueProcessing`) only reaches into IPFS when a chunk-hash comparison actually disagrees.
- **Open research question (explicitly not locked here):** subtask output today is saved as **one blob per subtask** (`ProcessingManager.cpp:1514-1636`), but the tolerance fallback needs to diff a **single chunk's** bytes within that blob. The exact slicing/offset mechanism to recover one chunk's numeric data from the fetched blob is left to research/planning — user explicitly OK'd deferring this rather than deciding it live.

### Tolerance threshold source (XNODE-02)
- **D-03:** When a job declares a `quantScale`/`byteQuantMode` (Phase 14's schema mechanism), derive the numeric tolerance threshold from it (e.g., grid-step-based bound tied to the configured `S`/`N`) rather than using an unrelated fixed constant — ties the fallback's strictness to each job's own configured precision, matching the ROADMAP's framing that the fallback "compares against configured precision/tolerance values."
- **D-04:** When a job declares no precision at all (Phase 14's additive-fallback case — `quantScale`/`byteQuantMode` absent or invalid), fall back to `capture_diff`'s existing fixed constants (`kDefaultFloatRelativeThreshold = 1e-4`, `kDefaultByteAbsoluteThreshold = 1`, `capture_diff.cpp:50,53`) — mirrors Phase 14's own silent-fallback discipline (D-04/D-08 in `14-CONTEXT.md`) rather than inventing new fallback semantics.
- **Note:** the exact formula converting `quantScale`/`byteQuantMode` into a numeric threshold (e.g. `1/S` for float, mask-width-derived bound for byte) is Claude's Discretion / research territory — not decided here.

### `capture_diff` logic reuse (technical, not user-facing)
- `ComputeFloat32Diff`/`ComputeUint8Diff`/`ElementDiffStats` currently live in an **unnamed namespace inside `capture_diff.cpp`** (lines 40-234), compiled only into the `capture_diff` CLI executable (`SGProcessingManager/tools/capture/CMakeLists.txt:38-46`) — not a linkable library, and in a different module than `ValidateResults` (`SuperGenius/src/processing/`). This logic needs extraction into a shared, linkable location before `ValidateResults` can call it. Exact target (new small static lib, header-only utility alongside `quantization.hpp`, etc.) is Claude's Discretion.

### SECV-02 counter-test shape
- **D-05:** SECV-02 mirrors SECV-01's methodology **exactly** — a full pipeline test, not a narrow unit test. Two complete jobs (correct vs. deliberately corrupted, same shape as `secv01_counter_test.cpp`'s inline-JSON + fixture-swap pattern) run end-to-end through real subtask assignment, and the test asserts the corruption still surfaces — through the **fixed** `ValidateResults` (D-01 concatenation-bug fix) plus the **tolerance fallback** (D-03/D-04) acting together, proving XNODE-01b/XNODE-02 aren't jointly loose enough to also mask a genuine defect.
- **Note:** this is structurally new territory — the existing `secv01_counter_test.cpp`/`secv01_tex3d_counter_test.cpp` tests operate at the single-node `ProcessingManager::Process()` level (whole job run twice, `memcmp` on `artifactId`) and never exercise `ValidateResults`/`SubTaskResult`/subtask-queue plumbing at all. SECV-02's harness will need to actually exercise the subtask-result validation path (not just re-run the existing pattern verbatim) — exact test file location/name (new file vs. extending `processing_subtask_queue_manager_test.cpp`) is Claude's Discretion.

### Claude's Discretion
- Blob-to-chunk slicing/offset mechanism for the fetched output data (D-01's open research question).
- Exact quantScale/byteQuantMode → numeric-tolerance-threshold formula (D-03).
- Physical location for the extracted `capture_diff` comparison logic (shared lib, header-only, etc.).
- Exact SECV-02 test file name/location, and precisely how the two-job pipeline is wired to produce two `SubTaskResult`s that reach `ValidateResults` with a genuine chunk mismatch.
- Whether the fetch-on-mismatch path is synchronous/blocking inside `ValidateResults` or dispatched by its caller — not raised as a gray area since it didn't come up as a concern during discussion; treat as a normal implementation choice.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements & Roadmap
- `.planning/workstreams/sgproc-render/REQUIREMENTS.md` — XNODE-01b, XNODE-02, SECV-02 (the locked requirements for this phase); Out of Scope table (XNODE-01c exclusion)
- `.planning/workstreams/sgproc-render/ROADMAP.md` (Phase 15 section) — goal, SC1-SC5, the Phase 14→15 dependency note

### Prior Phase Context (source of mechanisms this phase reuses/extends)
- `.planning/workstreams/sgproc-render/phases/14-configurable-normalization-precision/14-CONTEXT.md` — D-01/D-02 (schema `parameters` mechanism for `quantScale`/`byteQuantMode`), D-04/D-05/D-07/D-08 (silent-fallback discipline this phase's D-04 mirrors), D-09/D-10 (SECV-01-style counter-test methodology this phase's D-05 replicates)
- `.planning/workstreams/sgproc-render/phases/13-re-validation-scope-boundary-documentation/13-CONTEXT.md` — D-03 (processor-level hash vs. manifest hash distinction — `ValidateResults` operates on processor-level `chunk_hashes`, not `combinedHash`/`manifestHash`); `capture_diff`'s per-chunk comparison origin
- `.planning/workstreams/sgproc-render/STATE.md` — "New evidence for QUANT-CFG-01" paragraph's semantic/Dice-overlap correctness-bar nuance: bit-exact hash equality may be the wrong bar entirely for segmentation-style workloads — directly motivates why this phase's tolerance fallback exists, not just a defensive afterthought

### Existing Code (Source of Truth)
- `SuperGenius/src/processing/processing_validation_core.hpp` (class decl, lines 22-79) / `processing_validation_core.cpp` — `ValidateResults` (signature `hpp:47-49`), the concatenation bug (`cpp:53-98`, specifically line 84's `insert(end(), ...)`), `CheckSubTaskResultHashes` (`cpp:173-198`), `ValidateIndividualResult` (separate, correct, single-subtask-only check — not implicated in the bug)
- `SuperGenius/src/processing/processing_subtask_queue_accessor_impl.cpp` — `FinalizeQueueProcessing` (lines 323-341, the sole call site of `ValidateResults`), `ValidateResultData` (lines 515+, existing `ipfs://` scheme validation on `ipfs_results_data_id`), `OnResultChannelMessage` (lines 385-419, existing `mirrorResultCallback`/IPFS-fetch-on-receipt pattern — a direct precedent for D-01's fetch-on-mismatch)
- `SuperGenius/src/processing/proto/SGProcessing.proto` — `SubTask` (chunk descriptors, lines 30-48: `chunkid`, `n_subchunks`), `SubTaskResult` (lines 90-98: `result_hash`, `chunk_hashes`, `ipfs_results_data_id` — no raw-data field, confirming D-01's "fetch, don't extend proto" decision)
- `SuperGenius/SGProcessingManager/src/processingbase/ProcessingManager.cpp:1514-1636` — the existing `FileManager::SaveASync`/IPFS-dual-save/`output_locations` block D-01 reuses; `outputUrl = output.get_source_uri_param()` (line 1535) is the "output uri in json" the user pointed to as the real source of truth
- `SuperGenius/SGProcessingManager/tools/capture/capture_diff.cpp` — `ComputeFloat32Diff`/`ComputeUint8Diff`/`ElementDiffStats` (lines 40-234, currently unnamed-namespace/CLI-only), `kDefaultFloatRelativeThreshold`/`kDefaultByteAbsoluteThreshold` (lines 50,53), per-chunk driver loop (lines 341-375) — the exact comparison technique D-03/D-04 reuse
- `SuperGenius/SGProcessingManager/tools/capture/CMakeLists.txt:38-46` — confirms `capture_diff` is `add_executable` only, not a linkable target today
- `SuperGenius/SGProcessingManager/include/util/quantization.hpp`, `src/util/quantization.cpp` — `ResolveQuantScale`/`ResolveByteQuantMode` (Phase 14), the per-job resolved values this phase's tolerance derivation (D-03) must reach
- `SuperGenius/test/src/processing_conformance_security/secv01_counter_test.cpp` — the existing corrupted-model/wrong-shader counter-test methodology (`memcmp` on `artifactId`, two full `ProcessingManager::Create`+`Process()` runs) that D-05 replicates at the pipeline level
- `SuperGenius/test/src/processing_conformance_security/secv01_tex3d_counter_test.cpp` — Phase 14's tex3d variant of the same pattern, useful as a second reference for the two-job-comparison shape
- `SuperGenius/test/src/processing/processing_subtask_queue_manager_test.cpp:395-440` — the only existing `ValidateResults` test (`TEST_F(..., ValidateResults)`); only exercises identical-hash and missing-result cases, never a genuine two-different-hashes-for-the-same-chunk case — the gap this phase closes

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `FileManager::SaveASync`/IPFS-dual-save path (`ProcessingManager.cpp:1585-1618`) and `OnResultChannelMessage`'s existing `mirrorResultCallback` fetch-on-receipt pattern (`processing_subtask_queue_accessor_impl.cpp:385-419`) — direct precedent/template for D-01's fetch-on-mismatch
- `capture_diff.cpp`'s `ComputeFloat32Diff`/`ComputeUint8Diff` — the exact numeric-diff technique to extract and reuse, not reimplement
- `secv01_counter_test.cpp`'s two-job correct-vs-corrupted pipeline pattern — direct template for SECV-02 (D-05)
- `ResolveQuantScale`/`ResolveByteQuantMode` (Phase 14) — the per-job precision values D-03's tolerance derivation reads

### Established Patterns
- Silent-fallback-to-fixed-constant on absent/invalid config (Phase 14's D-04/D-08) — replicated by this phase's D-04 for the tolerance threshold
- Pairwise (two-subtask) framing throughout ROADMAP SC1-5 — matches existing `processing_subtask_queue_manager_test.cpp` test shape (2 subtasks, 1 shared chunk); no N-way/consensus logic needed this phase

### Integration Points
- `ValidateResults`'s current signature (`hpp:47-49`) takes `SubTaskCollection`, `results` map, and an output `invalidSubTaskIds` set — it has no access today to per-job schema `parameters` (needed for D-03's `quantScale`/`byteQuantMode` lookup) or to any data-fetch capability (needed for D-01). Both are new inputs/capabilities this phase must thread in; exact signature change is Claude's Discretion.
- `chunks` map keys on `subTask.chunkstoprocess(chunkIdx).SerializeAsString()` (the serialized `ProcessingChunk` descriptor) to identify "same chunk" across subtasks — this key mechanism stays, only the concatenation-vs-comparison behavior at line 84 changes.

</code_context>

<specifics>
## Specific Ideas

- User's own framing of D-01: "IPFS is the right track, but really from the job result uri which is determined by output uri in json" — i.e., don't invent a new reference/lookup scheme; the job's declared `source_uri_param` per output (already flowing through `FileManager::SaveASync`) is the real source of truth, `ipfs_results_data_id` is just that same value surfacing on the proto.
- Tolerance should track each job's own configured precision (Phase 14), not a single global constant repeated from `capture_diff` — but the fixed constants remain the correct fallback for jobs that declare nothing, consistent with Phase 14's "additive, not breaking" discipline.

</specifics>

<deferred>
## Deferred Ideas

- **Blob-to-chunk slicing mechanism** — explicitly left open for research/planning rather than decided in this discussion (see D-01's open research question). Not a scope-creep deferral — it's within this phase's work, just not pre-decided.
- **Actual cross-node consensus/redundant-execution orchestration plumbing (XNODE-01c)** — explicitly out of scope per REQUIREMENTS.md, unrelated to this phase's comparison-mechanism work.
- **Extracting `capture_diff`'s comparison logic to a shared library** is in-scope mechanical work for this phase (not deferred) — noted under Claude's Discretion above, not here, since it's required for D-03/D-04 to function at all.

### None further — discussion stayed within phase scope

</deferred>

---

*Phase: 15-Validation Comparison Mechanism*
*Context gathered: 2026-08-14*
