---
phase: 09-processor-pass-graph-conformance-suites
plan: 10
subsystem: processingbase
tags: [determinism, content-hash, artifacts, execution-manifest, gtest, ctest]

# Dependency graph
requires:
  - phase: 09 (plan 08)
    provides: corrected schema fixtures/inline JSON literals (Gap 1) so valid-job acceptance tests pass
  - phase: 09 (plan 09)
    provides: granular error propagation, model-format, pass-type validation (Gaps 2/4/5)
provides:
  - Deterministic ProcessOutput.combinedHash across separate Process() calls with identical inputs
  - Zero-initialized ExecutionManifest fields (no stack-garbage leakage into the hashed serialization)
  - Manifest self-hash computed over a timing-zeroed copy, decoupling wall-clock provenance from content identity
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns: ["Hash-input copy pattern: copy the live struct, zero out fields that are legitimate per-run provenance data (not content identity), hash the copy — while the returned/live struct keeps its real values"]

key-files:
  created: []
  modified:
    - SuperGenius/SGProcessingManager/src/processingbase/ProcessingManager.cpp

key-decisions:
  - "combinedHash/manifest.manifestHash are computed over a separate ExecutionManifest hashInput copy with startTimeUsec/endTimeUsec/wallClockUsec zeroed, rather than modifying SerializeManifest()/ComputeManifestHash()/the struct layout itself — preserves byte-for-byte compatibility with the existing Phase 08 artifact_serializer_test.cpp round-trip tests, which explicitly verify real timestamps survive serialize/deserialize"
  - "ProcessOutput output{} (empty-brace aggregate init) mirrors the existing Artifact art{} pattern a few lines later in the same function — both are plain aggregates with no user-declared constructors, so brace-init recursively zero-initializes every member lacking its own default member initializer"

patterns-established: []

requirements-completed: [TEST-06]

coverage:
  - id: D1
    description: "Two ProcessingManager::Process() calls with identical inputs (different manager instances) produce identical ProcessOutput.combinedHash"
    requirement: "TEST-06"
    verification:
      - kind: unit
        ref: "SuperGenius/test/src/processing_conformance_hashing/output_hashing_test.cpp#OutputHashingTest.ContentHashDeterministic"
        status: pass
    human_judgment: false
  - id: D2
    description: "No regression to the other 3 hashing conformance tests, or to the other 5 conformance suites (schema, executor, capability, migration, cancellation)"
    requirement: "TEST-06"
    verification:
      - kind: unit
        ref: "SuperGenius/test/src/processing_conformance_hashing/output_hashing_test.cpp#OutputHashingTest.ContentHashChangesOnDifferentInput"
        status: pass
      - kind: unit
        ref: "SuperGenius/test/src/processing_conformance_hashing/output_hashing_test.cpp#OutputHashingTest.ChunkHashesPresent"
        status: pass
      - kind: unit
        ref: "SuperGenius/test/src/processing_conformance_hashing/output_hashing_test.cpp#OutputHashingTest.PersistenceRoundTrip"
        status: pass
      - kind: integration
        ref: "ctest -R processing_conformance_(schema|executor|hashing|migration|cancellation|capability), full 6-binary sweep"
        status: pass
    human_judgment: false

duration: 20min
completed: 2026-08-06
status: complete
---

# Phase 09 Plan 10: Deterministic ProcessOutput.combinedHash (Gap 3) Summary

**Fixed two concrete, unrelated-to-MNN causes of non-deterministic `combinedHash`: brace-initialize `ProcessOutput` so `ExecutionManifest`'s char/uint8_t array fields no longer leak indeterminate stack memory into the hash, and compute the manifest self-hash over a timing-zeroed copy so legitimate per-run wall-clock provenance data no longer varies the content-identity hash.**

## Performance

- **Duration:** ~20 min
- **Tasks:** 2 completed (1 code change + 1 verification-only regression sweep)
- **Files modified:** 1

## Accomplishments

- `ProcessOutput output;` → `ProcessOutput output{};` in `ProcessingManager::Process()` — recursively zero-initializes every `ExecutionManifest` field lacking a default member initializer (`attemptId`, `taskId`, `subtaskId`, `tokenizerIdentity`, `adapterIdentity`, `quantizationIdentity`, `shaderIdentity`, `manifestHash`, unused tail of `inputArtifactHashes`/`outputArtifactHashes`), matching the pre-existing `Artifact art{}` pattern a few lines later
- Manifest self-hash computation changed from hashing the live `manifest` directly to hashing a local `ExecutionManifest hashInput = manifest;` copy with `startTimeUsec`/`endTimeUsec`/`wallClockUsec` zeroed — `manifest.manifestHash` and `output.combinedHash` are both derived from this deterministic copy, while `output.manifest` (returned to the caller) retains its real, unmodified timing values for provenance (ARTF-04)
- `SerializeManifest()`, `DeserializeManifest()`, `ComputeManifestHash()`, and the `ExecutionManifest`/`Artifact` struct layouts were left completely untouched, per plan scope — this preserves the existing Phase 08 `artifact_serializer_test.cpp` round-trip guarantees over real timestamps
- Verified `OutputHashingTest.ContentHashDeterministic` (previously failing) now passes, with the other 3 hashing tests unaffected
- Ran the full 6-binary regression sweep from the original UAT repro session (schema, executor, hashing, migration, cancellation, capability) — all 6 report 0 failures, 100% pass, ctest exit code 0. This closes out the last of the 4 originally-failing conformance binaries (schema, executor, hashing, capability), alongside the 2 always-passing ones (migration, cancellation)

## Task Commits

Task 1 was committed atomically inside the `SGProcessingManager` submodule (nested inside `SuperGenius`); Task 2 was verification-only (no files modified, no commit):

1. **Task 1: Zero-initialize ProcessOutput and exclude volatile timing fields from the manifest hash input** - `35db547` (fix)
2. **Task 2: Full regression sweep across all 6 Phase 09 conformance suites** - verification-only, no commit (all 6 binaries: 0 failures)

Submodule pointer bumps:
- `SuperGenius` repo: `388110d8` (docs) — bumps `SGProcessingManager` f1e289f9..35db547
- Outer `GeniusNetwork` repo: `178fb29` (docs) — bumps `SuperGenius` 458b885..388110d

**Plan metadata:** committed separately at the outer repo level (see final commit below)

## Files Created/Modified

- `SuperGenius/SGProcessingManager/src/processingbase/ProcessingManager.cpp` - `ProcessOutput output{}` brace-init; manifest self-hash now computed over a timing-zeroed `hashInput` copy instead of the live `manifest`

## Decisions Made

- Kept the hash-input-copy approach entirely inside `ProcessingManager::Process()` rather than touching `ComputeManifestHash()`/`SerializeManifest()` — this is the minimal-blast-radius fix that satisfies both determinism (this plan) and the pre-existing byte-for-byte serialization round-trip tests (Phase 08) simultaneously
- `output.manifest`'s live timing fields (`startTimeUsec`/`endTimeUsec`/`wallClockUsec`) are never mutated — only a throwaway copy used solely as the hash function's input is modified, so ARTF-04's provenance requirement is unaffected

## Deviations from Plan

None - plan executed exactly as written. Both tasks matched the `<action>`/`<verify>`/`<done>` instructions verbatim.

## Issues Encountered

None. Build and the full `ctest -R "processing_conformance_(schema|executor|hashing|migration|cancellation|capability)"` sweep succeeded on the first attempt after implementing Task 1. One unrelated pre-existing untracked file (`SuperGenius/test/src/processing_datatypes/.gitignore`) was observed in `git status` but is out of scope for this plan (not created by this plan's changes) — left untouched, not committed.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- All 6 named Phase 09 conformance test binaries (`processing_conformance_schema_test`, `processing_conformance_executor_test`, `processing_conformance_hashing_test`, `processing_conformance_capability_test`, `processing_conformance_migration_test`, `processing_conformance_cancellation_test`) are fully green (0 failures each), matching the exact repro command from the original UAT session
- This closes Gap 3, the last of the 4 originally-failing conformance binaries tracked by Phase 09's gap-closure plans (09-08, 09-09, 09-10)
- No blockers for phase completion

---
*Phase: 09-processor-pass-graph-conformance-suites*
*Completed: 2026-08-06*

## Self-Check: PASSED

Modified file `SuperGenius/SGProcessingManager/src/processingbase/ProcessingManager.cpp` exists on disk. Task 1 commit (`35db547`) is present in the `SGProcessingManager` submodule's git history; submodule pointer bump commits (`388110d8` in `SuperGenius`, `178fb29` in the outer repo) are present in their respective histories.
