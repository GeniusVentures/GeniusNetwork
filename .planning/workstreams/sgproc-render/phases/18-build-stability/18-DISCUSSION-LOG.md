# Phase 18: Build Stability - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-08-20
**Phase:** 18-Build Stability
**Areas discussed:** Closure bar for BUILD-01, Flaky dispatch test, Cross-repo scope

---

## Closure bar for BUILD-01

Before asking, Claude reproduced the bug against current HEAD (fresh same-day Debug build, real NVIDIA GPU present): `ProcessingDatatypesTest`, `ProcessingDispatchTest`, and `vulkan_init_concurrency_test` all passed cleanly across 4 separate runs (standalone and via `ctest`). Git history showed commit `528a92a` ("Fix hang on OSX", 2026-08-06) already restructured `capability_validator.cpp`'s `BuildSnapshot()` to avoid the exact self-deadlock pattern described in the pending todo — predating both the todo's filing (2026-08-10) and Phase 18's creation (2026-08-17).

| Option | Description | Selected |
|--------|-------------|----------|
| Verify-and-close | Document evidence, add a regression test pinning the scenario, close BUILD-01 without further locking-model changes | (see notes) |
| Deeper defensive audit | Audit every `VulkanInitMutex` call site + concurrent-stress testing before declaring closed | |
| Let the planner decide | Capture both options in CONTEXT.md, don't lock now | |

**User's choice:** Did not select directly — instead surfaced new information: a separate downstream project (`GeniusCognitiveSystem/GNUS-NEO-SWARM`) has integration tests that skip specifically to dodge this bug, and the user wants those tests to work. This reframed the discussion (see "Cross-repo scope" below). Combined with the final cross-repo scoping answer ("Confirm SuperGenius-side only, note the rest"), the effective decision is **Verify-and-close** for the SuperGenius side (D-01–D-03 in CONTEXT.md), with the NEO-SWARM angle carried forward as a deferred lead rather than in-phase work.
**Notes:** User's underlying goal: "I want these tests to work at least" (referring to NEO-SWARM's `test_sgprocessing_pipeline`).

---

## Flaky dispatch test

While reproducing the trio via `ctest`, one of four runs hit a flaky failure unrelated to `VulkanInitMutex`: `processing_dispatch_test` failed with a "Failed to open file (Windows)" error (looks like a CWD-relative test-fixture path issue), followed by an apparent stall before `vulkan_init_concurrency_test`'s result printed. It did not reproduce on 3 subsequent runs.

| Option | Description | Selected |
|--------|-------------|----------|
| Out of scope — note only | Record as observation/deferred idea, don't chase it | ✓ |
| Worth a quick look in-phase | Confirm whether it's a real intermittent bug or environmental noise | |
| File as its own todo | Capture as a new pending todo for a future phase | |

**User's choice:** Out of scope — note only.
**Notes:** Captured as D-05 in CONTEXT.md's decisions, and again under Deferred Ideas.

---

## Cross-repo scope (NEO-SWARM)

Claude found `GeniusCognitiveSystem/GNUS-NEO-SWARM/test/integration/test_sgprocessing_pipeline.cpp` has two tests (`Fp4UltraFormat_DispatchesToTensorProcessor`, `LlmDataType_JobReachesRegisteredProcessor`) that `GTEST_SKIP()` whenever a real Vulkan device is present, citing this exact tracked bug. The skip-guard was added 2026-08-18 (after the `528a92a` fix already existed in `SuperGenius`) and NEO-SWARM's own `04-VERIFICATION.md` documents the skip as *expected*/designed behavior on a real-device host — a deferral to sgproc-render Phase 18, not an independent fresh repro of a hang in that exact binary.

| Option | Description | Selected |
|--------|-------------|----------|
| Yes — make it the real acceptance bar | BUILD-01 not done until NEO-SWARM's two tests run for real and pass; touches a file in a different repo | |
| Confirm SuperGenius-side only, note the rest | Keep this phase's edits inside GeniusNetwork/SuperGenius; record the NEO-SWARM finding as a lead for a future follow-up | ✓ |

**User's choice:** Confirm SuperGenius-side only, note the rest.
**Notes:** Captured as D-04 in CONTEXT.md's decisions, with the full lead documented under Deferred Ideas and Canonical References for whoever picks it up later.

---

## Claude's Discretion

- Evidence bar for closure: Windows-with-real-GPU accepted as sufficient (no explicit multi-platform re-verification ask; ROADMAP's SC1-3 don't specify a platform).
- Exact form/location of the new regression test (extend `vulkan_init_concurrency_test.cpp` vs. a new dedicated test) left to planning/research.

## Deferred Ideas

- NEO-SWARM's stale skip-guard in `test_sgprocessing_pipeline.cpp` — strong, evidence-backed lead for a future todo/phase in the `GeniusCognitiveSystem`/`neoswarm` workstream (also needs to check whether their own build's separately-reported `get_third_party_dir()` CMake configure blocker is resolved).
- The flaky `processing_dispatch_test` CWD-relative file failure observed once during repro, not reproduced since.
