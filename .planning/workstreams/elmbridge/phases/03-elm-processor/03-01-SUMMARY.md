---
phase: 03-elm-processor
plan: 01
subsystem: mnn-fork
tags: [mnn, llm, fork-patch, sampler-seed, cancel]
provides: [MNN::Transformer::Llm::cancel, MNN::Transformer::Llm::kGnusLlmForkPatchLevel, sampler seed config key]
affects: [thirdparty/MNN, thirdparty submodule pointer]
requires: [MNN_Ultra_v2 @ 01b6f314]
tech-stack:
  added: []
  patterns: [config-key seed via merged config_, public cancel one-liner, configure-time fork marker]
key-files:
  created: []
  modified:
    - thirdparty/MNN/transformers/llm/engine/src/sampler.cpp
    - thirdparty/MNN/transformers/llm/engine/include/llm/llm.hpp
key-decisions:
  - "D-12 seed read from merged config_ in Sampler ctor (masked to uint32 mt19937 width); config-key style, no setter API"
  - "D-13 cancel() as public one-liner setting mContext->status = USER_CANCEL; benign-race comment per TIMEOUT pattern"
  - "D-14 kGnusLlmForkPatchLevel = 1 marker for SGProcessingManager configure-time grep"
requirements-completed: [GEN-01, GEN-02]
coverage:
  - deliverable: "Sampler constructor reads config_['seed'] and seeds mRng (32-bit masked)"
    verification:
      - kind: command
        ref: "git -C thirdparty/MNN diff MNN_Ultra_v2..dev_elmruntime --stat (2 files, 20 insertions)"
        status: pass
    human_judgment: false
  - deliverable: "Public Llm::cancel() + kGnusLlmForkPatchLevel marker in installed llm.hpp"
    verification:
      - kind: command
        ref: "Select-String thirdparty/build/Windows/Release/MNN/include/llm/llm.hpp 'void cancel()' + 'kGnusLlmForkPatchLevel'"
        status: pass
    human_judgment: false
  - deliverable: "MNN static lib rebuilt with patches (sampler.obj + llm.obj compiled post-commit)"
    verification:
      - kind: command
        ref: "obj timestamps 20:36:55/20:36:57 vs commit 20:35:16; MNN.lib 20:36:59"
        status: pass
    human_judgment: false
  - deliverable: "Behavioral determinism proof (same seed byte-identical) on a real model"
    human_judgment: true
    rationale: "Requires the staged Qwen fixture — executed by plan 03-04 fixture legs; not provable in this plan"
duration: 18 min
completed: 2026-09-11T20:40:00-04:00
---

# Phase 3 Plan 1: MNN Fork Patches Summary

Sampler-seed and Llm::cancel fork patches landed on the vendored MNN fork branch, MNN rebuilt from a clean external-project tree, and the thirdparty submodule pointer advanced — the innermost two levels of the five-level commit chain.

## Accomplishments

- **D-12 seed patch** — `Sampler::Sampler` now reads `config->config_["seed"]` (int64, masked `& 0xFFFFFFFFull` to the `std::mt19937` uint32 seed width) and calls `mRng.seed(...)` before the mConfig assignments; comment documents the set_config-BEFORE-load ordering requirement (Sampler constructed inside `Llm::load()` at llm.cpp:306).
- **D-13 cancel patch** — public `void cancel() { mContext->status = LlmStatus::USER_CANCEL; }` beside `getContext()`, with the callable-from-any-thread / benign-race / no-reason-parameter doc comment.
- **D-14 fork marker** — `static constexpr int kGnusLlmForkPatchLevel = 1;` in the same public section; comment states SGProcessingManager's CMake greps the installed llm.hpp for it.
- **MNN rebuild** — cleared the external project's configure/build/install stamps and the MNN-build tree to force a full rebuild (ExternalProject does not reliably rebuild on SOURCE_DIR edits despite BUILD_BYPRODUCTS); verified `sampler.obj` + `llm.obj` compiled at 20:36 (post-commit 20:35), fresh `MNN.lib` installed 20:36:59, and the installed `<MNN_INCLUDE_DIR>/llm/llm.hpp` carries both `void cancel()` and `kGnusLlmForkPatchLevel`.
- **Commit chain levels 1–2** — MNN repo: `04855552` on branch `dev_elmruntime` (diff vs `MNN_Ultra_v2`: exactly 2 files, 20 insertions); thirdparty repo: `1a0ad3e` on branch `dev_almadocker` changing only the MNN pointer. SuperGenius/root pointer commits deferred to plan 03-04 Task 3 per the plan.

## Commits

| Repo | SHA | Message |
|------|-----|---------|
| thirdparty/MNN | `04855552` | feat(llm): GNUS fork patches - sampler seed config key + Llm::cancel() (elmbridge 03-01, D-12/D-13/D-14) |
| thirdparty | `1a0ad3e` | chore: bump MNN to dev_elmruntime (elmbridge 03-01 sampler-seed + Llm::cancel fork patches) |

## Deviations from Plan

**[Rule 1 - rebuild enforcement] ExternalProject stamps force-cleared** — Found during: Task 2 | Issue: the plan anticipated ExternalProject might not rebuild on source edits; standard rebuild risked stale library | Fix: deleted `MNN-configure`/`MNN-build`/`MNN-install`/`MNN-done` stamps plus the `MNN-build` tree before invoking the MNN target | Files: none (build-tree state only) | Verification: fresh obj timestamps + installed header content | Commit: n/a (build state).

**Total deviations:** 1 auto-fixed. **Impact:** none — conservative full rebuild, identical result with stronger provenance.

## Issues Encountered

None.

## Next Phase Readiness

Ready for 03-02 (independent file set) and 03-03 (compiles against patched MNN: seed flows via set_config, cancel via the public method, marker greppable in the installed header).
