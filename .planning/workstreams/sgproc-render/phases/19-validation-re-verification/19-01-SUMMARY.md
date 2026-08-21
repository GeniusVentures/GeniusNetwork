---
phase: 19-validation-re-verification
plan: 01
subsystem: testing
tags: [gtest, protobuf, sha256, mnn, cross-hardware, validation, capture-format]

# Dependency graph
requires:
  - phase: 15-validation-comparison-mechanism
    provides: "ProcessingValidationCore::ValidateResults' 5-arg overload + AttemptToleranceFallback (unmodified, exercised here)"
  - phase: 13-re-validation-scope-boundary-documentation
    provides: "The original VALD-01 chunk-10 diagnostic (maxAbsDelta=3.0517578125e-05) and the S=2^15 quantScale derivation this phase's tolerance bound depends on"
provides:
  - "2 new TEST cases in processing_validation_core_test.cpp proving ValidateResults/AttemptToleranceFallback genuinely closes VALD-01's residual chunk-10 gap"
  - "19-REVERIFICATION.md — CLOSED classification with cited evidence"
  - "A fresh, checked-in 2-machine .cap capture pair + capture_diff cross-check for the MNN float32 fixture, replacing Phase 13's now-unreadable archive"
  - "Discovery + documentation of a DeserializeCaptureFile backward-compatibility regression (pre-Phase-16 .cap files unreadable by current tooling)"
affects: [future-capture-format-backward-compat-fix, milestone-v2.3-close]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Direct-unit-level ValidateResults exercise via public SGProcessing::SubTaskCollection/SubTaskResult protobufs (ChunkContribution is private, cannot be constructed directly) against real cross-hardware captured bytes, not synthetic buffers"
    - "Test-file-scoped spdlog::set_level(debug) to surface an existing production debug log line as citable ctest evidence, without touching production code"

key-files:
  created:
    - .planning/workstreams/sgproc-render/phases/19-validation-re-verification/19-REVERIFICATION.md
    - .planning/workstreams/sgproc-render/phases/19-validation-re-verification/captures/mnn-float_Fuus-Mac-mini.local---macOS_20260821T221542.cap
    - .planning/workstreams/sgproc-render/phases/19-validation-re-verification/captures/mnn-float_Mofu---Windows_20260821T221735.cap
    - .planning/workstreams/sgproc-render/phases/19-validation-re-verification/captures/diff-mnn-float-vald02-fresh.json
  modified:
    - SuperGenius/test/src/processing/processing_validation_core_test.cpp
    - SuperGenius/test/src/processing/CMakeLists.txt
    - .planning/workstreams/sgproc-render/REQUIREMENTS.md
    - .planning/workstreams/sgproc-render/ROADMAP.md
    - .planning/workstreams/sgproc-render/STATE.md

key-decisions:
  - "Presented the DeserializeCaptureFile backward-compat regression as a 3-way checkpoint (document as still-open / fix the parser / fresh capture); user chose fresh 2-machine capture over touching production code"
  - "Fresh capture independently reproduced Phase 13's exact original chunk-10 signature (maxAbsDelta=3.0517578125e-05, maxUlpDistance=2048) via a fresh capture_diff cross-check, proving the substitution didn't change what's being re-verified"
  - "VALD-02 classified CLOSED — AttemptToleranceFallback genuinely engages and resolves chunk 10 (no error, zero subtasks invalidated); the underlying numeric divergence still exists, but the comparison mechanism correctly absorbs it, which is what this phase asked"
  - "Raised spdlog::set_level(debug) inside one TEST case only (test-file-scoped, no production change) to surface AttemptToleranceFallback's existing debug log line as citable numeric evidence"
  - "DeserializeCaptureFile's pre-Phase-16 backward-compat regression documented but left unfixed (D-04 scope boundary); filed as a new STATE.md deferred item for a future phase"

patterns-established:
  - "When a plan's named fixture becomes unreadable mid-execution due to an unrelated regression discovered via independent double-confirmation (own test + unmodified production CLI tool), escalate as a Rule 4 architectural checkpoint rather than silently reinterpreting or working around it in the test"

requirements-completed: [VALD-02]

coverage:
  - id: D1
    description: "ValidateResults/AttemptToleranceFallback genuinely closes VALD-01's residual chunk-10 gap when fed the real captured Mac/Windows MNN float32 bytes across all 15 chunks"
    requirement: "VALD-02"
    verification:
      - kind: unit
        ref: "SuperGenius/test/src/processing/processing_validation_core_test.cpp#ProcessingValidationCoreTest.Vald02ChunkHashSelfCheckMatchesPublishedRefit"
        status: pass
      - kind: unit
        ref: "SuperGenius/test/src/processing/processing_validation_core_test.cpp#ProcessingValidationCoreTest.Vald02FullFixtureValidateResultsToleranceOutcome"
        status: pass
    human_judgment: false
  - id: D2
    description: "19-REVERIFICATION.md's CLOSED classification, and the honest documentation of the DeserializeCaptureFile backward-compat regression discovered mid-phase"
    verification: []
    human_judgment: true
    rationale: "Classifying a re-verification outcome as CLOSED/PARTIALLY CLOSED/STILL OPEN, and deciding how to handle an unrelated production regression discovered mid-phase, are interpretive judgments over test evidence — appropriate for a human/orchestrator sign-off on this milestone's last requirement, not a pure pass/fail automatable check."

duration: 60min
completed: 2026-08-21
status: complete
---

# Phase 19 Plan 1: Validation Re-Verification Summary

**Two new gtest cases prove `ProcessingValidationCore::ValidateResults`/`AttemptToleranceFallback` genuinely closes VALD-01's residual chunk-10 MNN float32 gap (`maxAbsDelta=3.0517578125e-05` within the `2.0/32768.0` bound), re-run against a fresh 2-machine capture after Phase 13's archived fixture was found unreadable by current tooling.**

## Performance

- **Duration:** ~60 min active work (spanning two checkpoint pauses for external actions: a Windows Debug thirdparty MNN rebuild, and a fresh 2-machine `.cap` capture session)
- **Tasks:** 3 (plus 2 mid-flight follow-up commits responding to checkpoint resolutions)
- **Files modified:** 5 tracked (2 SuperGenius test-layer files, 3 workstream docs) + 3 new checked-in evidence files

## Accomplishments

- Added `Vald02ChunkHashSelfCheckMatchesPublishedRefit` and `Vald02FullFixtureValidateResultsToleranceOutcome` to `processing_validation_core_test.cpp`, feeding real captured Mac/Windows MNN float32 bytes through the unmodified, production 5-arg `ValidateResults`/`AttemptToleranceFallback` code path across all 15 chunks
- Confirmed, with fresh evidence, that the tolerance-fallback mechanism (shipped unmodified since Phase 15) genuinely engages for chunk 10 and resolves it as a match: `maxAbsDelta=3.0517578125e-05` sits within the D-03 bound `2.0/32768.0=6.103515625e-05`; `ValidateResults` reports no error and invalidates zero subtasks
- Discovered and independently confirmed (via the unmodified `capture_diff` CLI, not just this phase's own new test code) a real, previously-unknown regression: `DeserializeCaptureFile` can no longer parse any pre-Phase-16 `.cap` file, because Phase 17's own fix (`bf7e694`) made it unconditionally require the newer, larger manifest region with no backward-compatible fallback
- Took a fresh 2-machine capture (per the user's explicit choice at a Rule-4 checkpoint) that independently reproduced Phase 13's exact original chunk-10 signature, proving the substitution didn't change the underlying phenomenon being re-verified
- Closed out VALD-02 — the last of v2.3's 8 requirements — with an honest, evidence-cited CLOSED classification in `19-REVERIFICATION.md`

## Task Commits

All commits live in the `SuperGenius` submodule unless noted otherwise (outer repo on `dev_persisprocresults`):

1. **Task 1: Add VALD-02 re-verification TEST cases + wire CMake** — `a99a47c8` (test)
2. **Task 1 follow-up: re-point fixture at fresh capture (D-01-REVISED)** — `5fed94b2` (fix)
3. **Task 1 follow-up: raise log level for evidence capture** — `76efdc0c` (test)
4. **Task 3: write 19-REVERIFICATION.md, close out REQUIREMENTS/ROADMAP/STATE** — `579eae9` (docs, outer repo)
5. **Submodule pointer bump** — `7e0932c` (chore, outer repo)

_Task 2 (run tests, capture evidence) produced no file changes — verbatim ctest output captured and cited directly in 19-REVERIFICATION.md._

## Files Created/Modified

- `SuperGenius/test/src/processing/processing_validation_core_test.cpp` — 2 new `TEST` cases + `ReadFileBytes` helper + `spdlog::set_level(debug)` evidence-capture line
- `SuperGenius/test/src/processing/CMakeLists.txt` — `sgproccapture` link + `VALD02_CAPTURES_DIR` compile definition
- `.planning/workstreams/sgproc-render/phases/19-validation-re-verification/19-REVERIFICATION.md` — outcome document, CLOSED classification with cited evidence
- `.planning/workstreams/sgproc-render/phases/19-validation-re-verification/captures/` — fresh `.cap` pair + `capture_diff` cross-check JSON (new evidence artifacts)
- `.planning/workstreams/sgproc-render/REQUIREMENTS.md` — VALD-02 checked off, traceability updated, 8/8 v2.3 requirements complete
- `.planning/workstreams/sgproc-render/ROADMAP.md` — Phase 19 marked complete, per-SC outcome annotations, Progress table updated
- `.planning/workstreams/sgproc-render/STATE.md` — Deferred Items resolved, frontmatter/Current Position reflect all 4 v2.3 phases complete, new deferred item filed for the capture-format regression

## Decisions Made

- Presented the `DeserializeCaptureFile` backward-compat regression as a 3-way checkpoint (document as still-open / fix the parser / fresh capture) rather than silently choosing; user chose fresh 2-machine capture, explicitly overriding 19-CONTEXT.md's original D-01 "no new hands-on capture session" constraint (recorded as D-01-REVISED)
- Classified VALD-02 as CLOSED: the underlying cross-hardware numeric divergence (one S=2^15 grid-step rounding-boundary tie-break) still physically exists and is not eliminated — what closes is whether `ValidateResults`' comparison mechanism correctly absorbs it, which the fresh evidence proves it does
- Raised `spdlog::set_level(spdlog::level::debug)` inside one `TEST` case only (test-file-scoped logging verbosity, zero production code/behavior change) so `AttemptToleranceFallback`'s existing production debug log line became visible as citable numeric evidence in the captured ctest output
- Left the `DeserializeCaptureFile` regression unfixed per D-04's scope boundary (no production code modified this phase); documented in `19-REVERIFICATION.md` and filed as a new `STATE.md` deferred item for a future phase to pick up

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking, escalated] Windows Debug thirdparty MNN missing `FP4DequantUtils.hpp`**
- **Found during:** Task 1's build verification
- **Issue:** `processing_processor_mnn_tensor.cpp` (pre-existing, unmodified) failed to compile: `MNN/FP4DequantUtils.hpp` not found in the Windows Debug thirdparty tree, though present in the Release tree
- **Resolution:** Per `AgentDocs/CLAUDE.md`'s explicit "the user manages thirdparty builds separately — do not attempt to build thirdparty" rule, this was escalated as a `human-action` checkpoint rather than self-resolved. User rebuilt the Windows Debug thirdparty tree; build then succeeded cleanly.
- **Committed in:** No code change required — environment-only fix

**2. [Rule 4 - Architectural, escalated] Phase 13's archived `.cap` fixture unreadable by current tooling**
- **Found during:** Task 2 (running the new tests against the D-01-specified fixture)
- **Issue:** `DeserializeCaptureFile` returned `false` for both halves of Phase 13's exact named `.cap` pair. Ruled out as a bug in this phase's own new test code via two independent confirmations: (a) byte-level analysis showing the file is well-formed under the *old* (pre-Phase-16) manifest layout, and (b) the unmodified `capture_diff` CLI tool failing identically on the same files. Root-caused via git history to `SGProcessingManager` commit `bf7e694` (Phase 17), which made the parser unconditionally require the newer `MANIFEST_V2_SERIALIZED_SIZE` region with no backward-compatible fallback for pre-Phase-16 files.
- **Resolution:** Escalated as a 3-way decision checkpoint (document as still-open / fix the parser out-of-scope / take a fresh capture) rather than silently picking a path, since fixing the parser would touch production code outside the plan's declared scope, and substituting the fixture reverses an explicit prior decision (D-01). User chose a fresh 2-machine capture; independently confirmed via `capture_diff` to reproduce Phase 13's exact original signature before re-pointing the test fixture and CMake path at it.
- **Files modified:** `SuperGenius/test/src/processing/processing_validation_core_test.cpp` (fixture filenames), `SuperGenius/test/src/processing/CMakeLists.txt` (`VALD02_CAPTURES_DIR` path)
- **Verification:** Full 7-test ctest re-run passed 100%, including both new `Vald02*` cases against the fresh fixture
- **Committed in:** `5fed94b2`

---

**Total deviations:** 2 escalated (1 environment/build-infra, 1 architectural/fixture-substitution) — both resolved via explicit checkpoints to the user rather than silently worked around, per Rule 3's package-install-style exclusion (build infra) and Rule 4 (architectural decision requiring human input).
**Impact on plan:** No production code was modified in either case. The fixture substitution (D-01-REVISED) is fully documented in `19-CONTEXT.md` and `19-REVERIFICATION.md`, with independent numeric proof that the substitution didn't change what was being re-verified.

## Issues Encountered

None beyond the two deviations above, both fully resolved.

## User Setup Required

None — no external service configuration required. (The Windows Debug thirdparty rebuild was a one-time environment fix already completed by the user during this phase's execution.)

## Next Phase Readiness

- All 4 phases of v2.3 (Deferred Gap Closure) are now complete: Phase 16 (Manifest Evolution), Phase 17 (Render-Path Cross-Hardware Tolerance), Phase 18 (Build Stability), Phase 19 (Validation Re-Verification). All 8 v2.3 requirements are complete per `REQUIREMENTS.md`'s coverage summary.
- Ready for `/gsd-complete-milestone` to formally close v2.3.
- Open follow-up (not blocking): `DeserializeCaptureFile`'s pre-Phase-16 backward-compatibility regression remains unfixed — affects any future attempt to re-analyze Phase 13's archived `.cap` captures with current tooling. Documented in `19-REVERIFICATION.md` and `STATE.md`'s Deferred Items table; not queued to a specific future phase yet.

---
*Phase: 19-validation-re-verification*
*Completed: 2026-08-21*

## Self-Check: PASSED

All created files verified present on disk; all 5 cited commit hashes (`a99a47c8`, `5fed94b2`, `76efdc0c` in SuperGenius; `579eae9`, `7e0932c` in the outer repo) verified present in git history.
