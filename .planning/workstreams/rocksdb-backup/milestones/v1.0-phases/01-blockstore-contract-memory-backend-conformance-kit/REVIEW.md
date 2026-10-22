---
phase: 01-blockstore-contract-memory-backend-conformance-kit
reviewed: 2026-10-20
reviewer: inline (execute-phase code-review gate)
scope: thirdparty/sgns-blockstore/** (new repo), thirdparty/build/CommonTargets.cmake (entry), thirdparty/.github/workflows/build.yml (ctest step)
severity_counts:
  critical: 0
  major: 0
  minor: 4
  info: 2
---

# Phase 1 Code Review

## Critical

None.

## Major

None.

## Minor

**M-1: Interface const-qualification frozen out**
`BlockStore::Get/Has/GetSize` and their overrides are non-const (per the CONTEXT-locked signatures). Adding `const` later is an implementer-breaking change to a frozen v1.0.0 contract. Nothing is wrong today; the cost is a one-way door taken without an explicit note. Suggested: record as a standing note for any pre-public-release review.

**M-2: CorruptData fault is a no-op for empty payloads**
`MemoryBlockStore::Get` flips `bytes[0]` only when the payload is non-empty; an empty block under `FaultKind::CorruptData` verifies clean and returns intact. Harmless (the seam's tests use non-empty payloads) but undocumented in the fault's Doxygen. Suggested: one-line @note on `FaultKind::CorruptData`.

**M-3: Superbuild entry exports only the CONFIG_DIR variable**
`_FINDPACKAGE_SGNS_BLOCKSTORE_CONFIG_DIR` exists; the libp2p precedent also exports LIBRARY_DIR/INCLUDE_DIR convenience variables. Consumer wiring is explicitly out of this milestone's scope, so this is additive-later by design — recorded so Phase 2+ wiring remembers.

**M-4: `EvictLocal` skips the D-08 hash gate**
A blake2b CID handed to `EvictLocal` succeeds as a no-op erase instead of throwing like every data-path op. Behaviorally harmless (erasing an absent key), but inconsistent with the every-op entry-gate story. Suggested: align in Phase 2's `LocalBlockStore::EvictLocal`.

## Info

**I-1:** `PutMany` evaluates the fault gate at entry and again per element via `Put` — redundant but harmless.
**I-2:** kit helper functions (`SpanOf`/`MakeCid`) duplicate small logic in the backend test TU; the kit must stay self-contained (D-12), so the duplication is the cheaper option.
