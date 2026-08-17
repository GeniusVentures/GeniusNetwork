# Phase 16: Manifest Evolution - Context

**Gathered:** 2026-08-17
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 08 (2026-08-05) shipped the execution manifest's baseline shape — self-contained, fixed-field, little-endian binary layout, no schema evolution mechanism — and explicitly deferred four gaps: a Merkle tree over chunk hashes (ARTF-07), content-defined chunking (ARTF-08), human-readable error message strings (ARTF-09), and schema evolution support for the binary format (ARTF-10). Phase 16 closes this deferred scope.

**This discussion substantially narrowed the phase from the roadmap's literal 4-requirement scope to 2 requirements actually implemented (ARTF-09, ARTF-10), with the other two (ARTF-07, ARTF-08) closed out as "won't implement — not applicable" after grounding each against how the system's actual architecture and protocols work.** See Decisions below.

**Depends on:** Phase 15 (v2.2, shipped) — first phase of v2.3; independent of Phases 17-19 in this milestone.

</domain>

<decisions>
## Implementation Decisions

### ARTF-07 (Merkle tree over chunk hashes) — Won't implement, not applicable
- **D-01:** No Merkle tree is built this phase. `Artifact::chunkHashes` (flat list, up to 1024 entries, `artifact_types.hpp:67-68`) already gives full per-chunk localization — every real consumer already has the complete list, not just a compact root.
- **D-02:** Concretely: task results travel over graphsync as protobuf, which already includes every subtask's chunk hashes. A verifier redoes the processing and compares hashes directly — it never holds a root without the underlying list. The only scenario where a root-only proof would matter (a caller with a root but not the chunk list) doesn't occur in this system's actual flow.
- **D-03:** The chunk-hash-mismatch fallback path (what happens when hashes disagree) is XNODE-01c territory (cross-node consensus/redundant execution), already explicitly out of scope per REQUIREMENTS.md — not something this decision reopens.
- **D-04:** Status should read "Won't implement — not applicable," not "deferred." Deferred implies a future revisit driven by resourcing; this is a reasoned architectural conclusion that the gap doesn't exist given how graphsync/protobuf already deliver chunk hashes. Updating REQUIREMENTS.md's traceability table and ROADMAP.md's Phase 16 requirements/success-criteria list to reflect this (removing/reframing ARTF-07 with this rationale) is one of this phase's own plan tasks — mirrors how Phase 13 corrected its own scope wording in-plan.

### ARTF-08 (content-defined chunking) — Won't implement, not applicable
- **D-05:** No content-defined chunking is built this phase. `block_len` (schema-driven, `Dimensions.hpp`) is defined by the job poster at submission time — it is their parameter, not SGProcessingManager's to renegotiate.
- **D-06:** If source data no longer fits the job's declared `block_len` (e.g. a re-fetched http/file-sourced input changed shape), that is a bad-job condition to surface as a failure, not a gap to reconcile via smarter chunking.
- **D-07:** IPFS/bitswap-sourced (CID-addressed) inputs are immune to the "small edit invalidates every downstream chunk hash" problem by construction — a changed input is a different CID, i.e. a different job, not an edit. `FileManager` (`thirdparty/AsyncIOManager/include/FileManager.hpp`) does support non-CID sources (http/file prefixes registered alongside the bitswap path), so the underlying problem CDC solves is reachable in principle — but per D-06, that mismatch is the job poster's responsibility, not something to solve here.
- **D-08:** Same status convention as ARTF-07: "Won't implement — not applicable," with REQUIREMENTS.md/ROADMAP.md updates to reflect this handled as a Phase 16 plan task.

### ARTF-09 (human-readable error message in manifest) — Implement
- **D-09:** Add a new fixed-max-size string field to `ExecutionManifest` carrying `ProcessingError::message` (currently populated at every processor error site — `processing_processor.hpp`/`processing_processor_mnn_*.cpp` — but discarded down to the bare `TerminalState` enum at `ProcessingManager::ProcessInternal()`, `ProcessingManager.cpp:1319-1356`).
- **D-10:** Cap at 256 bytes, matching Phase 08's D-06 (which already anticipated this exact cap for error message strings). Overflow is truncated silently — no truncation marker — consistent with the manifest's existing fixed-max-size-with-inline-storage convention.
- **D-11:** Populate for all terminal states that carry a `ProcessingError` (not scoped to one particular error stage) — general-purpose diagnostic value, not tied to one specific consumer.
- **D-12:** No specific external consumer drove this — "any caller reading only the manifest artifact can see why it failed" is the whole goal, consumable in `outcome` form per the codebase's existing `outcome::result`/`outcome::failure` convention.

### ARTF-10 (schema evolution for binary manifest format) — Implement
- **D-13:** This is the mechanism that makes ARTF-09's new field addable at all without breaking every existing manifest blob and the hardcoded-offset round-trip tests — today `SerializeManifest`/`DeserializeManifest` (`artifact_serializer.cpp:144,233`) hard-fail on any size mismatch (`bytes.size() != EXPECTED_SIZE`), and there is no version/magic field anywhere in the format.
- **D-14:** Must prove both compatibility directions per ROADMAP.md's Phase 16 SC4: a manifest written by the updated writer (new optional fields present) still parses successfully with an unmodified older reader (new fields ignored); a manifest written before the new fields existed still parses successfully with the updated reader (new fields default/absent).
- **D-15:** Exact versioning layout (magic+version header vs. trailing optional/TLV section, where the version tag lives, how the existing hardcoded-offset tests in `artifact_serializer_test.cpp` get extended without breaking) is left to planning/research — no user preference was expressed beyond the two compatibility directions above, which are already locked by the roadmap's success criteria.

### Claude's Discretion
- Exact binary layout for ARTF-10's versioning mechanism (magic number placement, version field size/type, whether new fields go in a trailing TLV region or a new fixed-but-versioned layout).
- Exact new field name/type for ARTF-09's error message (e.g. `char errorMessage[256]`) and its offset within `ExecutionManifest`.
- How `artifact_serializer_test.cpp`'s existing hardcoded-literal-offset assertions get extended to cover the new field(s) without breaking existing ones.
- Exact wording/table edits to REQUIREMENTS.md and ROADMAP.md documenting ARTF-07/ARTF-08 as "Won't implement — not applicable."

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements & Roadmap
- `.planning/workstreams/sgproc-render/REQUIREMENTS.md` — ARTF-07..10 locked requirements (traceability table currently shows all four as "Phase 16 | Pending" — ARTF-07/08 need updating to "Won't implement" per this discussion)
- `.planning/workstreams/sgproc-render/ROADMAP.md` (Phase 16 section) — goal, success criteria (SC1-SC4), requirement traceability — SC1/SC2 (Merkle/CDC) are now moot per this discussion's decisions; SC3 (error message) and SC4 (schema evolution both directions) remain the actual bar

### Prior Phase Context
- `.planning/workstreams/sgproc-render/phases/08-structured-artifacts-execution-manifests/08-CONTEXT.md` — D-04 (custom deterministic binary serialization, no protobuf), D-06 (fixed max sizes + inline storage — anticipated the 256-byte error string cap this phase implements), D-09 (chunk structure is job-defined, grounds ARTF-08's won't-implement decision), D-13 (self-contained manifest), D-14 (sentinel values, no conditional layout — direct tension with ARTF-10's need for optional fields, to be reconciled in planning), D-15 (original deferral of error message string, now being closed by ARTF-09)

### Source of Truth
- `SuperGenius/SGProcessingManager/include/artifacts/execution_manifest.hpp` — `ExecutionManifest` struct (line 34) — target of ARTF-09's new field and ARTF-10's versioning
- `SuperGenius/SGProcessingManager/include/artifacts/artifact_serializer.hpp` (lines 35, 45-64) + `src/artifacts/artifact_serializer.cpp` (`SerializeManifest` line 144, `DeserializeManifest` line 233) — fixed-offset serialization to be extended; note the `manifestHash`-zeroing `const_cast` pattern (lines 173-178, 227-228) must be preserved by any refactor
- `SuperGenius/SGProcessingManager/include/artifacts/artifact_types.hpp` — `Artifact` struct (line 45), `chunkHashCount`/`chunkHashes[1024]` (lines 67-68), `TerminalState` enum (line 28, `Error = 4` comment explicitly cites D-15)
- `SuperGenius/SGProcessingManager/include/processors/processing_processor.hpp` (lines 46-50) — `ProcessingError { stage, message }` — source of the message ARTF-09 threads through
- `SuperGenius/SGProcessingManager/src/processingbase/ProcessingManager.cpp` (lines 1319-1356, 1442+) — where `ProcessingError::message` is currently discarded to the enum and where manifest assembly happens; exact insertion point for ARTF-09
- `SuperGenius/SGProcessingManager/include/util/sha256.hpp` / `src/util/sha256.cpp` — `sgns::sgprocmanagersha::sha256()` — existing hashing utility (not needed this phase since ARTF-07 is won't-implement, but referenced for context)
- `SuperGenius/SGProcessingManager/test/artifacts/artifact_serializer_test.cpp` — existing round-trip tests (`ArtifactSerializeRoundTrip.AllFieldsMatch` line 61, `ManifestSerializeRoundTrip.AllFieldsMatch` line 216); several assert against **hardcoded literal byte offsets** (e.g. `bytes[1344]`, `bytes[1112]`) — ARTF-10's field additions must not silently break these; they need corresponding extension
- `SuperGenius/SGProcessingManager/generated/Dimensions.hpp` (line 47, `block_len`) + `gnus-processing-schema.json` (line 104) — job-poster-defined chunk size parameter, grounds ARTF-08's won't-implement decision
- `thirdparty/AsyncIOManager/include/FileManager.hpp` — pluggable loader/saver registration by URL prefix (`https`, `file`, `mnn` cited in header comments) alongside the IPFS bitswap path — confirms non-CID input sources exist, referenced in ARTF-08's D-07

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`ProcessingError { stage, message }`** (`processing_processor.hpp:46-50`) — already populated with real human-readable strings at every processor error site. ARTF-09 threads this existing, live data into the manifest; no new error-message generation needed.
- **Fixed-offset serialization pattern** (`artifact_serializer.cpp`) — `SerializeManifest`/`DeserializeManifest` already establish the `memcpy`-at-`OFF_*`-constant convention ARTF-10 extends rather than replaces.

### Established Patterns
- **Fixed-field, little-endian, no-versioning binary format** (Phase 08 D-04/D-05) — `MANIFEST_SERIALIZED_SIZE = 5649`, `ARTIFACT_SERIALIZED_SIZE = 33880`, both hard-fail deserialization on any size mismatch today. ARTF-10 is the first phase to introduce any flexibility into this.
- **Sentinel values over conditional layout** (Phase 08 D-14) — the existing philosophy explicitly avoided union/tagged sections. ARTF-10 necessarily introduces *some* form of optional-field handling; reconciling this with D-14's original "no conditional layout" intent is a planning-level design question, not a re-litigation of D-14 itself.
- **`outcome::result`/`outcome::failure`** — existing codebase convention (e.g. `ProcessingManager::GetCidForProc` returns `outcome::result<...>`) that ARTF-09's error message should be consumable through, per this discussion.

### Integration Points
- **`ProcessingManager::ProcessInternal()`** (`ProcessingManager.cpp:1319-1356` for the stage→`TerminalState` mapping, manifest assembly at 1442+) — exact point where `processResult.error->message` is one call-site away from being captured instead of only logged.
- **`artifact_serializer_test.cpp`** — any new field must extend (not silently break) the existing hardcoded-offset assertions; this is the concrete backward/forward-compat proof surface for ARTF-10's SC4.

</code_context>

<specifics>
## Specific Ideas

Key domain context from discussion:
- **Content-addressing already solves what CDC would solve, for CID-sourced inputs.** The user's framing: IPFS/bitswap CIDs make "editing" a category error — a changed input is a new object, not a revision. CDC's value is real only for the http/file-sourced fetch path, but even there, the user's view is that a `block_len` mismatch against a job's declared parameters is the job poster's failure to surface, not SGProcessingManager's problem to solve.
- **Graphsync already delivers what Merkle proofs would deliver.** Task results travel as protobuf over graphsync, already containing every subtask's chunk hashes — the scenario a Merkle root+inclusion-proof would uniquely serve (verify one chunk without the full list) doesn't arise in this system's actual verification flow (verifiers redo processing and compare directly).
- **"Won't implement — not applicable" is a distinct status from "deferred."** The user explicitly rejected "deferred" wording for ARTF-07/08 because it implies a future revisit driven by resourcing constraints, when the actual conclusion is architectural: the gap doesn't exist given how this system's protocols (graphsync/protobuf, CID addressing) already work.
</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope. (ARTF-07/ARTF-08 are not "deferred ideas" in the roadmap-backlog sense; they are this phase's own conclusion, captured above as "won't implement.")

</deferred>

---

*Phase: 16-Manifest Evolution*
*Context gathered: 2026-08-17*
