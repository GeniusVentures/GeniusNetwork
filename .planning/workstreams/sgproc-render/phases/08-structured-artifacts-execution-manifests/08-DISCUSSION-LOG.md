# Phase 08: Structured Artifacts & Execution Manifests - Discussion Log

**Date:** 2026-08-05
**Mode:** Default (interactive)

---

## Area 1: Artifact Identity Model

### Q1: Artifact ID generation
- **Options:** Content-hash-based | Structured key (job+pass+binding) | Hybrid
- **Selected:** Content-hash-based (SHA-256 of raw artifact bytes)
- **Rationale:** Consistent with Phase 06 D-08 (executor identity = SHA-256). Content-addressable — same output always yields same ID.

### Q2: Pre-production references
- **Options:** Write manifest last | Placeholder + replace | Manifest uses structured keys
- **Selected:** Write manifest last
- **Rationale:** Simple — artifacts produced first, hashes computed, then manifest assembled with all IDs known.

### Q3: ID stability across runs
- **Options:** Same bytes = same ID | Always unique per run
- **Selected:** Same bytes = same ID
- **Rationale:** Content-addressable. Enables deduplication, caching.

### Q4: Hash input scope
- **Options:** Raw bytes only | Bytes + metadata envelope
- **Selected:** Raw bytes only
- **Rationale:** Pure content-addressability. Metadata (resource name, format, dimensions) are separate fields on the artifact record.

---

## Area 2: Manifest Serialization Format

### Q1: Serialization approach
- **Clarification:** User asked about serialization destination. Clarified that serialization is primarily for hashing the manifest within SGProcessingManager, not wire format (per 06 D-05).
- **Options:** Deterministic binary (custom) | Direct hash (no serialization) | Protobuf canonical
- **Selected:** Deterministic binary (custom)
- **Rationale:** C++ struct only — consistent with 06 D-05. Serialized bytes can be passed to SuperGenius as opaque blob.

### Q2: Binary encoding rules
- **Options:** Fixed-field, little-endian | TLV | Fixed-field, network byte order
- **Selected:** Fixed-field, little-endian
- **Rationale:** Matches native in-memory layout on x86/ARM. Simple, fast.

### Q3: Variable-length data handling
- **Options:** Fixed max + inline | Length prefix + offset table | Fixed-size only, refs for large data
- **Selected:** Fixed max + inline
- **Rationale:** Keeps fixed-field layout truly fixed. Strings capped, overflow rejected at construction.

---

## Area 3: Hash Scheme for Artifacts

### Q1: Chunking strategy
- **Clarification:** User noted that chunks are defined by job parameters, not arbitrary byte-splitting. MNN processors already produce per-chunk hashes. ARTF-03 formalizes existing behavior.
- **Options:** Include now (formalize existing) | Content hash only for now
- **Selected:** Include now (formalize existing)
- **Rationale:** Processors already produce chunk hashes — artifact record gives them a structured home. Minimal new code.

### Q2: Hash algorithm consistency
- **Clarification:** User noted everything already uses SHA-256.
- **Decision:** SHA-256 everywhere (content hash, chunk hashes, executor identity). Noted as non-controversial.

---

## Area 4: Migration Adapter Lifespan

### Q1: Adapter duration
- **Options:** Temporary (remove before ship) | Long-lived (keep until SuperGenius updates)
- **Clarification:** User said "just update SuperGenius at the same time."
- **Decision:** Temporary adapter, removed before ship. SuperGenius updated simultaneously.

### Q2: API transition strategy
- **Options:** Replace entirely | Dual API during transition
- **Clarification:** User noted "Before it was just getting a byte array, so I think we're just replacing."
- **Decision:** Clean replacement. No coexistence.

---

## Area 5: Manifest Scope & Structure

### Q1: Manifest completeness
- **Options:** Self-contained | Lightweight hash-chain
- **Selected:** Self-contained
- **Rationale:** Single source of truth for the execution record. All ARTF-04 fields inline.

### Q2: Inapplicable field handling
- **Options:** Sentinel values for N/A | Union/tagged section
- **Selected:** Sentinel values for N/A
- **Rationale:** Predictable binary layout. Zero hashes for inapplicable identities (model, shader).

### Q3: Error details format
- **Options:** Terminal state enum + fixed message | Terminal state only | Structured error (code + category + message)
- **Selected:** Terminal state only
- **Rationale:** Enum sufficient for signing/verification. Error details in logs.

---

## Deferred Ideas
- Merkle tree over chunks — deferred (flat list sufficient)
- Content-defined chunking — deferred (job-defined structure is natural model)
- Error message strings in manifest — deferred (logs)
- Schema evolution for binary format — deferred (new phase if needed)

## Claude's Discretion Areas
- Exact C++ struct layouts for Artifact, ArtifactRecord, ExecutionManifest
- Exact fixed-field binary layout (offsets, sizes, max string/array lengths)
- Exact TerminalState enum member names
- ProcessingManager integration for artifact record construction
- Chunk hash extraction from existing processor output
- SHA-256 hash implementation reuse
