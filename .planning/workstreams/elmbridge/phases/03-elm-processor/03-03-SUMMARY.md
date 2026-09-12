---
phase: 03-elm-processor
plan: 03
subsystem: sgprocmanager-processors
tags: [elm, processor, envelope, stop-string, cancel, seeding, factory-registration]
provides: [sgns::elmruntime::ElmEnvelope, ElmFinishReason, ElmEnvelopeToJson, ElmStopStringStreamBuf, sgns::sgprocessing::ElmProcessor, StartProcessingElm, SGPROC_MNN_LLM_FORK_PATCHES, ElmEntryPreflight bridge]
affects: [ProcessingManager factory, processors CMake, ElmSmokeCheck]
requires: [03-01, 03-02]
tech-stack:
  added: []
  patterns: [gated TU with fail-closed #else, streambuf-poll cancel wiring, dump_config round-trip assert, plain-value cross-generated-set bridge]
key-files:
  created:
    - SuperGenius/SGProcessingManager/include/elmruntime/ElmEnvelope.hpp
    - SuperGenius/SGProcessingManager/src/elmruntime/ElmEnvelope.cpp
    - SuperGenius/SGProcessingManager/include/elmruntime/ElmStopStringStreamBuf.hpp
    - SuperGenius/SGProcessingManager/src/elmruntime/ElmStopStringStreamBuf.cpp
    - SuperGenius/SGProcessingManager/include/processors/processing_processor_elm.hpp
    - SuperGenius/SGProcessingManager/src/processors/processing_processor_elm.cpp
    - SuperGenius/SGProcessingManager/include/elmruntime/ElmEntryPreflight.hpp
    - SuperGenius/SGProcessingManager/src/elmruntime/ElmEntryPreflight.cpp
    - SuperGenius/SGProcessingManager/test/elmruntime/elm_envelope_test.cpp
    - SuperGenius/SGProcessingManager/test/elmruntime/elm_stop_streambuf_test.cpp
  modified:
    - SuperGenius/SGProcessingManager/src/elmruntime/CMakeLists.txt
    - SuperGenius/SGProcessingManager/test/elmruntime/CMakeLists.txt
    - SuperGenius/SGProcessingManager/src/processors/CMakeLists.txt
    - SuperGenius/SGProcessingManager/src/processingbase/ProcessingManager.cpp
    - SuperGenius/SGProcessingManager/include/processingbase/ProcessingManager.hpp
    - SuperGenius/SGProcessingManager/src/elmruntime/ElmSmokeCheck.cpp
key-decisions:
  - "D-05/D-06/D-07: ElmStopStringStreamBuf with kOverlapSlack=16, byte-based UTF-8-safe window, earliest-match-position-wins across ALL stops, two separate intent latches (stop-string vs cancel) firing one idempotent cancel hook"
  - "Pitfall 4 resolution: SetExternalCancelPoll wires execCtx.cancelToken.IsCancelled() per token flush; zero ProcessManager callback changes"
  - "Pitfall 2/3: set_config BEFORE load + dump_config round-trip assert on every key (seed included); NO timeout_ms (deadline flows via cancel token per Phase 1 D-03)"
  - "max_output_tokens absent -> key omitted from set_config AND -1 sentinel to response() (model's llm_config.json default; no 512 hard default)"
  - "Cross-generated-set conflict resolved via ElmEntryPreflight plain-value bridge (root set in processor TU, fallback set in the bridge TU)"
  - "Factory: DataType::LLM now constructs ElmProcessor (MNN_Llm lambda replaced); base StartProcessing fails closed naming StartProcessingElm"
requirements-completed: [GEN-01, GEN-02, GEN-03, RES-01]
coverage:
  - deliverable: "Envelope JSON matrix (all four finish reasons, error key presence/absence, exact key set)"
    verification:
      - kind: tests
        ref: "sgprocelmruntime_envelope_test.exe ElmEnvelopeTest (5 legs PASSED)"
        status: pass
    human_judgment: false
  - deliverable: "Stop-string semantics: exclusion, split-across-writes, earliest-wins, no-match, window negative leg, cancel-intent latch, one-shot hook, overflow path"
    verification:
      - kind: tests
        ref: "sgprocelmruntime_envelope_test.exe ElmStopStreamBufTest (11 legs PASSED)"
        status: pass
    human_judgment: false
  - deliverable: "Gated processor TU compiles with split locks + registration + marker"
    verification:
      - kind: command
        ref: "SGProcessors.lib built clean; ElmProcessor registered (ProcessingManager.cpp:462); both lock names in ElmSmokeCheck; SGPROC_MNN_LLM_FORK_PATCHES CMake detection present"
        status: pass
    human_judgment: false
  - deliverable: "Regressions: cache tests (smoke check under split locks), mnn_llm shim, envelope tests"
    verification:
      - kind: tests
        ref: "cache 18 PASSED / mnn_llm 2 PASSED / envelope 16 PASSED, all exit 0"
        status: pass
    human_judgment: false
  - deliverable: "End-to-end generation on a real model (SC-1/SC-2/SC-3 behavioral legs)"
    human_judgment: true
    rationale: "Requires staged fixture — executed by plan 03-04 fixture legs"
duration: 95 min
completed: 2026-09-11T21:35:00-04:00
---

# Phase 3 Plan 3: ELM Processor Summary

The phase's core deliverable: the ELM processor TU orchestrating acquire → preflight → split-locked session create → set_config-assert-load → streambuf-wrapped response → LlmContext reconciliation → envelope, plus the no-MNN envelope/streambuf units with green unit tests, factory registration, and the D-14 fork-patch compile marker.

## Accomplishments

- **Task 1 — no-MNN units** — `ElmEnvelope` (enum + ToString/FromString + ElmEnvelopeToJson with the exact key set; nested error object only on Error) and `ElmStopStringStreamBuf` (D-06 incremental overlap scan, kOverlapSlack=16, UTF-8 lead-byte back-off, D-09 two-latch disambiguation, one-shot injectable cancel hook). Target `sgprocelmruntime_envelope_test`: 16/16 legs green (envelope matrix 5, streambuf 11). CMake: sources in `sgprocmanagerelmruntime`, whole-binary add_test always, discovery gated on `SGPROC_TEST_DISCOVERY AND NOT CMAKE_CROSSCOMPILING`, TIMEOUT 120.
- **Task 2 — gated processor TU** — `ElmProcessor` with fail-closed base `StartProcessing` and the `StartProcessingElm(chunkhashes, promptText, stopStrings, elm, execCtx, cache, capabilityValidator)` seam. Flow per the plan: pre-cancel first; quicktype optionals materialized once (UB rule); Phase 1 default-fills (temperature/top_p 1.0; max_output_tokens/seed kept as presence-flags — absent → key omitted + -1 sentinel, never 512); cache Acquire with pin held by value (RAII on every return); preflight via the bridge + CheckElmResources (degraded-0 honored, nullptr validator = logged skip); LOAD_MODEL progress; createLLM under VulkanInitMutex ONLY; set_config + dump_config round-trip assert BETWEEN the locks; load under LlmLoadMutex; PushTeardown + post-load cancel re-check; response with `end_with=""` and the -1 sentinel, streambuf polling the cancel token per token; LlmContext-sourced counts with gen_seq_len mismatch warning; the complete D-08..D-11 finish-reason table (TIMEOUT→error-with-detail, CHECK_LLM_RUNNING early-return→error); envelope JSON + sha256 + budget check.
- **Task 3 — wiring** — CMake: ELM sources in the gated `_SGPROC_LLM_SOURCES` lists + `SGPROC_MNN_LLM_FORK_PATCHES` configure-time grep of the installed llm.hpp for `kGnusLlmForkPatchLevel` (degraded-path STATUS message for stock MNN); ProcessingManager: DataType::LLM factory constructs ElmProcessor; ElmSmokeCheck: lock scope split (createLLM ⊂ VulkanInitMutex, set_config unlocked, load ⊂ LlmLoadMutex) — cache tests re-prove the smoke check green under the split.

## Commits

| Repo | SHA | Message |
|------|-----|---------|
| SGProcessingManager | `8d6b25d` | feat(elmruntime): ELM envelope + stop-string streambuf units (elmbridge 03-03) |
| SGProcessingManager | `2aee930` | feat(processors): ELM processor TU - generation loop, seeded sampling, cancel, envelope (elmbridge 03-03) |
| SGProcessingManager | `d0f30ea` | feat(processors): ELM registration, fork marker, smoke-check lock split (elmbridge 03-03) |

## Deviations from Plan

**[Rule 1 - generated-set conflict] ElmEntryPreflight plain-value bridge added** — Found during: Task 2 | Issue: the plan's step (d) told the processor TU to call ExtractElmResourceRequirements directly, but that pulls the fallback elmruntime-manifest generated set into a TU that includes the root set (via SGNSProcMain.hpp for sgns::Elm) — the documented ClassMemberConstraints redefinition (C2011, verified by a failed build) | Fix: new `elmruntime::PreflightPinnedEntry(entryDir, declaredHash)` bridge TU holding the fallback includes, returning two plain uint64 values the processor feeds to CheckElmResources — exactly the pattern ElmResourcePreflight.hpp's header comment prescribes for this conflict | Files: +ElmEntryPreflight.hpp/.cpp, CMake | Verification: SGProcessors builds clean | Commit: d0f30ea.

**[Rule 2 - build errors] include + namespace fixes during first compile** — `#include <generated/Elm.hpp>` → SGNSProcMain.hpp (path not on include dirs); `sgns::LlmContext/LlmStatus` → `MNN::Transformer::` (types live in MNN's namespace, not sgns).

**[Rule 1 - unit test correctness] earliest-match-wins + window-leg test fixes** — Found during: Task 1 test run | Issue: the scan returned the first stop in LIST order (test EarliestOfTwoPresentMatches got offset 12, expected 6), and my window-negative test used "WOR" as the stop which literally matches its own prefix text | Fix: scan ALL stops and take the minimum match position; test now uses a genuinely incomplete "WO" prefix scrolled out of the window | Verification: 16/16 green.

**Total deviations:** 4 auto-fixed. **Impact:** none on contract — the bridge is additive and follows the documented cross-set pattern; all plan acceptance criteria still met.

## Issues Encountered

None unresolved.

## Next Phase Readiness

Ready for 03-04: the processor is registered and standalone-testable; the fixture legs will exercise determinism (SC-2), cancel latency (SC-3), locks (SC-5/D-02), and the stop-string parameter seam end-to-end on the staged Qwen bundle.
