# Phase 08: Structured Artifacts & Execution Manifests - Context

**Gathered:** 2026-08-05
**Status:** Ready for planning

<domain>
## Phase Boundary

Output artifacts are typed records with resource identity, format, dimensions, SHA-256 content hashes, per-chunk hashes, and producing-pass provenance — not loose byte buffers and newline-delimited strings. The execution manifest is a self-contained, fixed-field deterministic binary record capturing everything needed for hashing, signing, caching, and verification. Existing `ProcessingResult` callers are migrated via a temporary adapter (removed before ship); SuperGenius is updated simultaneously.

**Depends on:** Phase 07 (EXEC — artifacts need execution context for manifest fields like timings, terminal state, executor identity).

</domain>

<decisions>
## Implementation Decisions

### Artifact Identity Model (ARTF-01, ARTF-02)
- **D-01:** Content-hash-based artifact IDs — SHA-256 of raw artifact bytes. Content-addressable: same bytes across any execution produce the same ID. Enables deduplication, caching, and content-addressable storage. Consistent with Phase 06 D-08 (executor identity = SHA-256 of capability snapshot).
- **D-02:** Manifest written last — artifacts are produced first (IDs computed from final bytes), then the manifest is assembled with all IDs known. No placeholder/replacement complexity.
- **D-03:** Content hash covers raw artifact bytes only — metadata fields (resource name, format, dimensions, media type) are separate fields on the artifact record, NOT hashed into the content ID. Pure content-addressability.

### Manifest Serialization Format (ARTF-04, ARTF-05)
- **D-04:** Custom deterministic binary serialization — a `Serialize()` method producing fixed-order bytes, then SHA-256 hashed. No protobuf within SGProcessingManager (consistent with Phase 06 D-05: "C++ structs only"). The serialized bytes can be passed to SuperGenius as an opaque blob; SuperGenius handles wire serialization if needed.
- **D-05:** Fixed-field, little-endian layout — every field at a fixed offset, all multi-byte values in little-endian (native on x86/ARM). Struct-like — matches in-memory layout for simple types. No length prefixes needed for fixed-size fields.
- **D-06:** Fixed maximum sizes + inline storage for variable-length data — strings capped (e.g., 256 bytes for error messages), array counts capped. Data exceeding maximums is truncated or rejected at manifest construction time. Keeps the fixed-field layout truly fixed.

### Hash Scheme (ARTF-03)
- **D-07:** SHA-256 everywhere — content hash, chunk hashes, and executor identity all use SHA-256. One algorithm, one code path. Consistent with Phase 06 D-08. All existing processors already use SHA-256.
- **D-08:** Chunk hashes captured from existing processor output — MNN processors already produce per-chunk hashes and a combined subtask hash. The artifact record formalizes these in structured fields (chunk hash list + aggregate content hash). No new hashing behavior — just structured storage.
- **D-09:** Chunk structure is job-defined — chunks come from job processing parameters (subtask chunking model), not arbitrary byte-splitting. The artifact record carries however many chunk hashes the job produced.

### Migration Adapter (ARTF-06)
- **D-10:** Temporary adapter — old `ProcessingResult` shape (hash + output names + byte buffers + output-location string) delegates to new artifact records internally. Removed before Phase 08 ships. Follows Phase 07 D-18/D-19 pattern.
- **D-11:** SuperGenius updated simultaneously — `ProcessingResult` replaced by artifact records + manifest in the same PR set. Clean break, no dual-API period.
- **D-12:** API replacement, not coexistence — the old byte-array API is replaced entirely. New API returns typed artifact records directly. No transitional dual-return path.

### Manifest Scope & Structure (ARTF-04, ARTF-05)
- **D-13:** Self-contained manifest — all ARTF-04 fields are inline: execution/attempt/task/subtask/pass IDs, executor identity, model/tokenizer/adapter/shader/quantization identities, input/output artifact hashes, start/end times, terminal state, error details, and resource-use summary. Manifest is the single source of truth for the execution record.
- **D-14:** Sentinel values for inapplicable fields — model identity = zero hash when no model was used; shader identity = zero hash when no shader. All fields always present at fixed offsets — no conditional layout, no union/tagged section.
- **D-15:** Terminal state enum only in manifest — `TerminalState` enum values: `Success`, `Cancelled`, `Timeout`, `BudgetExceeded`, `Error`. No error message string in the manifest (error details live in logs). Follows Phase 07's distinct typed failure pattern.

### Claude's Discretion
- Exact C++ struct layouts for `Artifact`, `ArtifactRecord`, and `ExecutionManifest` (field ordering, types, max sizes).
- Exact fixed-field binary layout (field offsets, byte sizes, max string lengths, max array counts).
- Exact `TerminalState` enum member names and underlying type.
- How `ProcessingManager` integrates artifact record construction into the existing `Process()` dispatch flow.
- How chunk hashes are extracted from existing processor output and mapped into artifact record fields.
- SHA-256 hash implementation reuse — existing code paths from Phase 06 executor identity hashing.
- Whether artifact records and manifest are stack-allocated within the `Process()` scope or heap-allocated with smart pointers.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements & Roadmap
- `.planning/workstreams/sgproc-render/REQUIREMENTS.md` — ARTF-01..06 locked requirements for this phase
- `.planning/workstreams/sgproc-render/ROADMAP.md` — Phase 08 goal, success criteria, and requirement traceability

### Prior Phase Context
- `.planning/workstreams/sgproc-render/phases/06-capability-validation-foundation/06-CONTEXT.md` — D-05 (C++ structs only, no protobuf — grounds D-04), D-06 (flat list pattern for structured results), D-08 (SHA-256 executor identity — grounds D-01/D-07), D-19 (caller-responsibility — grounds D-11 simultaneous update)
- `.planning/workstreams/sgproc-render/phases/07-cancellable-execution-context/07-CONTEXT.md` — D-14 (unified teardown stack — artifact resources register for cleanup), D-18/D-19 (adapter pattern — grounds D-10/D-11), D-01/D-10 (callback patterns), D-05 (unified terminal path with distinct error codes — grounds D-15 TerminalState enum)

### Prior Phase Context (v1.0)
- `.planning/workstreams/sgproc-render/phases/03-renderprocessor-implementation-determinism/03-CONTEXT.md` — D-25..D-28 (per-stage error enum + message pattern — prior art for TerminalState enum design)
- `.planning/workstreams/sgproc-render/phases/02-schema-extension-shader-spir-v-validation-pipeline/02-CONTEXT.md` — SCHEMA-01..05 (schema-driven configuration — artifacts extend the existing schema pattern for output declarations)

### Source of Truth
- `SuperGenius/SGProcessingManager/include/processors/processing_processor.hpp` — `ProcessingResult` struct (hash, output names, byte buffers, output-location string) — the shape being replaced by artifact records (D-10/D-12)
- `SuperGenius/SGProcessingManager/src/processing_manager.cpp` — `Process()` dispatch — the code path where artifact record construction is integrated
- `SuperGenius/SGProcessingManager/include/capability/capability_types.hpp` — `CanExecuteResult` struct — prior art for structured C++ result types with flat lists (06 D-06)
- `SuperGenius/SGProcessingManager/include/capability/capability_validator.hpp` — executor identity hash pattern (06 D-08) — the SHA-256 code path reused for artifact/manifest hashing
- `SuperGenius/src/processing/` — SuperGenius processing layer that consumes `ProcessingResult` — the caller being updated simultaneously (D-11)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`ProcessingResult` struct** (`processing_processor.hpp`) — current output shape (hash + output names + byte buffers + output-location). The migration adapter (D-10) wraps this to delegate to new artifact records.
- **Executor identity SHA-256** (Phase 06, `capability_validator.hpp`) — existing SHA-256 hashing code path. Artifact content hashes (D-01) and manifest hashing (D-04) reuse the same hashing infrastructure.
- **MNN processor chunk hashing** — all 14 MNN processors already produce per-chunk hashes and combined subtask hashes. D-08 formalizes these in artifact record fields — no new hashing, just structured storage.
- **`CanExecuteResult`** (Phase 06, `capability_types.hpp`) — flat-list structured result pattern. Artifact record follows the same C++-struct-only philosophy (06 D-05).
- **`RenderProcessor::PushTeardown`/`RunTeardown`** (Phase 03, generalized in Phase 07 D-14) — artifact resources (buffers, file handles) register for cleanup via the unified teardown stack.

### Established Patterns
- **C++ structs only, no protobuf in SGProcessingManager** — Phase 06 D-05. Manifest serialization (D-04) and artifact records follow this. SuperGenius handles wire serialization.
- **SHA-256 for all hashing** — Phase 06 D-08 (executor identity), now extended to content hashes (D-01), chunk hashes (D-07), and manifest hashing (D-04).
- **Temporary adapter → clean break** — Phase 07 D-18/D-19. D-10/D-11 follow the same pattern: adapter during development, removed before ship, consumers updated simultaneously.
- **Flat list + enum tagging** — Phase 06 D-06 (`UnmetRequirement` list). Artifact chunk hash lists (D-08) follow the same flat-list convention.
- **Schema-driven output declarations** — Phase 02 SCHEMA-01..05. Artifact records extend this pattern: output bindings declare expected artifact types, formats, dimensions.

### Integration Points
- **`ProcessingManager::Process()`** — dispatch point where artifact records are constructed from processor output. The `ExecutionContext` (Phase 07) provides timestamps, terminal state, and executor identity for the manifest (D-13).
- **`ProcessingResult` → artifact record bridge** — the temporary adapter (D-10) maps old fields (hash → content hash, output names → resource names, byte buffers → artifact payload, output-location → manifest reference).
- **SuperGenius processing layer** (`SuperGenius/src/processing/`) — consumes `ProcessingResult` today. Updated simultaneously (D-11) to consume artifact records + manifest.
- **`FileManager::SaveASync`** — artifact payloads may be persisted. The teardown stack (07 D-14) ensures partial artifacts are cleaned up on cancel/timeout/failure.

</code_context>

<specifics>
## Specific Ideas

Key domain context from discussion:
- **Existing chunk hashing is the foundation** — MNN processors already hash per-chunk output. ARTF-03 is formalization, not invention. The artifact record gives existing hashes a structured home.
- **No new serialization dependencies** — custom deterministic binary, consistent with the project's C++-only philosophy. No protobuf, MessagePack, CBOR, or other serialization libraries added.
- **Clean break, not gradual migration** — SuperGenius updates alongside SGProcessingManager. No indefinite adapter, no dual-API period. This requires coordination but avoids permanent legacy cruft.
- **Manifest as single source of truth** — self-contained, not a lightweight wrapper around artifact hashes. All execution provenance in one record for signing and verification.
- **Sentinel values over conditional layout** — keeps the binary format simple and deterministic. Zero hashes for inapplicable identities; fixed offsets for everything.
</specifics>

<deferred>
## Deferred Ideas

- **Merkle tree over chunks** — deferred. Current flat chunk hash list is sufficient; Merkle tree adds complexity without a concrete verification use case.
- **Content-defined chunking (rolling hash)** — deferred. Job-defined chunk structure (D-09) is the natural model for SGProcessingManager's processing pipeline.
- **Error message strings in manifest** — deferred (D-15). Terminal state enum is sufficient for signing/verification; detailed error diagnostics remain in logs.
- **Schema evolution for binary format** — deferred. Fixed-field layout has no versioning mechanism. If manifest fields need to change in the future, a new manifest format version would be a new phase.
</deferred>

---

*Phase: 08-Structured Artifacts & Execution Manifests*
*Context gathered: 2026-08-05*
