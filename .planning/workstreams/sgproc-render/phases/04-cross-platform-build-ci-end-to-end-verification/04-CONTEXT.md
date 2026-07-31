# Phase 4: Cross-Platform Build, CI & End-to-End Verification - Context

**Gathered:** 2026-07-31
**Status:** Ready for planning

<domain>
## Phase Boundary

The render path (schema → shader validation → `RenderProcessor` execution → hash) is proven end-to-end across target platforms (Windows, Linux, macOS/MoltenVK) and continuously verified in CI, with zero regressions to existing MNN inference/retrain behavior. This phase adds CI wiring and E2E test fixtures — it does not change `RenderProcessor`'s implementation (Phase 3, complete) or the schema/shader pipeline (Phase 2, complete). Requirements: DETV-03, E2E-01, E2E-02, E2E-03.

</domain>

<decisions>
## Implementation Decisions

### DETV-03 — Hardware tier design (simplified from literal roadmap wording)
- **D-31:** No software Vulkan ICD (lavapipe/SwiftShader) is installed or vendored in CI, for now. This deliberately simplifies DETV-03's literal "hardware-independent tier via a software Vulkan ICD" framing — the user explicitly chose to skip software-ICD complexity rather than solve the "no single ICD covers all 3 platforms" problem (see rationale below).
  - **Rationale surfaced during discussion:** Mesa lavapipe is Linux-only (no official macOS build); SwiftShader covers all 3 platforms but needs building/vendoring specifically for macOS (and everywhere, if used uniformly) with no current thirdparty precedent. Rather than pick a per-platform hybrid (lavapipe Linux/Windows + SwiftShader macOS) or vendor SwiftShader everywhere, the user chose to drop the software-ICD tier entirely for this phase.
- **D-32:** In its place, **all Vulkan-device-dependent tests (pipeline construction, draw+readback, N≥10 determinism) are gated by a runtime GPU probe** (`vkEnumeratePhysicalDevices`, DISCRETE_GPU/INTEGRATED_GPU only — matches `RenderProcessor::IsAcceptable`'s existing device-type filter, `processing_processor_render.cpp:19-23`). This applies uniformly on every platform including macOS/MoltenVK, not just GPU-less Linux runners.
- **D-33:** Schema validation, GLSL→SPIR-V shader compile, and `spirv-val` (none of which need a `VkDevice` — see Phase 2's `ShaderCompiler`) **always run in CI regardless of GPU probe result**, on every platform, since they have no hardware dependency at all. Only the parts of DETV-03 that genuinely require a `VkInstance`/`VkDevice` are gated by D-32's probe.
- **D-34:** When the GPU probe finds no usable device, the gated test step is **skipped with a clear CI annotation** — not silently passed (e.g. a no-op green check) and not a hard CI failure. Confirmed applies across all self-hosted runners: `sg-ubuntu-linux` (modern AMD CPU), `sg-arm-linux` (recent ARM Minisforum box), `SG-WIN11` (modern AMD/Intel CPU), `gv-OSX-Large` (Tart VM on a high-end Mac) — none of these are assumed to have a real GPU; actual availability is discovered by the probe at CI runtime, not assumed at design time.
  - **Explicitly re-confirmed:** this includes macOS — do not assume the Tart VM has Metal/MoltenVK GPU passthrough just because it's a "high-end Mac" host; the probe governs, on this platform exactly like the others.

### E2E-01 — Scope of "actual distributed processing pipeline"
- **D-35:** E2E-01 means a **single-node round trip** through the real `ProcessingManager`/`RenderProcessor` code path — a real render-pass job definition submitted via `ProcessingManager::Process()`, producing a verified output hash. **Not** a multi-node network test (no IPFS/pubsub dispatch to a separate worker node).
  - **Rationale:** confirmed via codebase scout that no working multi-node test harness exists today — `test/src/processing_nodes/processing_nodes_test.cpp`'s network-facing cases are `DISABLED_*`, and `processing_service_test`/`processing_multi_test` (pubsub-based) are commented out / not wired into the build. There is no precedent to extend toward a real multi-node test in this phase.
  - **Pattern to mirror:** the existing `ProcessingSchemaTest.PosenetJobTest` (`test/src/processing_schema/processing_schema_test.cpp:210`, using a real `posenet-processing-job.json` fixture) establishes the project's convention of testing against a real, realistic job definition file rather than a synthetic minimal one. E2E-01's render test should follow the same shape — a real render-pass job definition fixture, run through the real dispatch path — rather than inventing a different test style. `test/src/processing_dispatch/processing_dispatch_test.cpp`'s `RenderPassSameNodeRepeatedExecutionProducesBitExactHash` (already added in Phase 3) is architecturally the same shape E2E-01 needs; planner should confirm during planning whether that existing test already satisfies E2E-01 or whether a distinct fixture/test is warranted (e.g. to keep DETV-01's determinism concern and E2E-01's "is this a real job" concern conceptually separate).

### CI wiring approach
- **D-36:** Extend the **existing** `SuperGenius/.github/workflows/cmake.yml` matrix directly — do not create a new, separate workflow file. New render-CI steps (GPU probe, gated pipeline/draw/determinism tests) are added into the existing per-platform jobs (Linux/Windows/OSX), reusing the existing runner-resolution (`resolve-runners` job) and CTest (`addtest()` convention) machinery as-is. Android/iOS jobs are unaffected (RenderProcessor is not in scope for those targets per CTX-01).

### E2E-03 — Zero regressions / concurrent stress test (largely already satisfied structurally)
- **Context surfaced during discussion:** Phase 1 already added `test/src/processing_vulkan_concurrency/vulkan_init_concurrency_test.cpp` (`VulkanConcurrentInitTest.RepeatedConcurrentInitNoRaceOrCrash`) — 25 iterations, 3 concurrent threads (MNN string job, MNN texture3d job, `RenderProcessor::StartProcessing` directly), gated on no crash/race. This is already registered via the standard `addtest()`/CTest convention and already runs on every CI matrix job's `ctest` step — no new CI wiring needed for the concurrency proof itself.
- **D-37:** Planner should treat E2E-03 primarily as a **verification/confirmation task** (confirm the existing test still passes cross-platform post-Phase-4 CI changes, confirm the full existing MNN suite stays green) rather than new test-authoring, unless research surfaces a specific gap in the existing 25-iteration/3-thread test's coverage.

### Claude's Discretion
- Exact CI step/job naming, GPU-probe implementation detail (small CMake/CTest helper vs. inline script check), and exact CTest label/tag scheme for gating GPU-dependent tests — mechanical CI authoring detail, not raised as a vision-level concern.
- Whether E2E-01's render job definition test is a new test case or a relabeling/promotion of the existing Phase 3 `RenderPassSameNodeRepeatedExecutionProducesBitExactHash` test — left to planner/researcher per D-35's note.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements & Roadmap
- `.planning/workstreams/sgproc-render/REQUIREMENTS.md` — DETV-03, E2E-01, E2E-02, E2E-03 locked requirements for this phase
- `.planning/workstreams/sgproc-render/ROADMAP.md` — Phase 4 success criteria. **Note:** DETV-03's literal "software Vulkan ICD" hardware-independent tier wording is superseded by D-31/D-32/D-33/D-34 above (GPU-probe-gated design) — planner/researcher should treat this CONTEXT.md as authoritative over the roadmap's original DETV-03 phrasing.

### Prior Phase Context
- `.planning/workstreams/sgproc-render/phases/01-vulkan-foundation-dispatch-plumbing/01-CONTEXT.md` — D-04/D-05 (shared `VulkanInitMutex`, concurrent-init stress test origin — directly relevant to E2E-03/D-37)
- `.planning/workstreams/sgproc-render/phases/03-renderprocessor-implementation-determinism/03-CONTEXT.md` — D-22/D-23 (fresh-build-per-job, sync teardown — relevant to repeat-run test behavior E2E-01/DETV-03 build on)
- `.planning/STATE.md` §"Blockers/Concerns" — pre-existing note that "CI currently has zero real-GPU or software-Vulkan-ICD signal, and zero macOS CI signal for Vulkan at all" — this phase's entire reason for existing

### Source of Truth (current state, pre-this-phase)
- `SuperGenius/.github/workflows/cmake.yml` — the existing CI matrix this phase extends (D-36). `resolve-runners` job (self-hosted runner discovery/fallback), per-platform `build`/`Run tests` steps, `libvulkan-dev`-only Linux Vulkan install (line ~520, loader only, no ICD)
- `SuperGenius/SGProcessingManager/src/processors/processing_processor_render.cpp:19-23` — `RenderProcessor::IsAcceptable`'s existing DISCRETE_GPU/INTEGRATED_GPU device-type filter, the exact check D-32's GPU probe should mirror
- `SuperGenius/test/src/processing_vulkan_concurrency/vulkan_init_concurrency_test.cpp` — existing concurrent-init stress test (D-37)
- `SuperGenius/test/src/processing_dispatch/processing_dispatch_test.cpp` — existing `RenderPassSameNodeRepeatedExecutionProducesBitExactHash` test (D-35)
- `SuperGenius/test/src/processing_schema/processing_schema_test.cpp:210` + `posenet-processing-job.json` — the "real job definition" test pattern E2E-01 should mirror (D-35)
- `SuperGenius/test/src/processing_nodes/processing_nodes_test.cpp` — disabled multi-node test cases (`DISABLED_ProcessNodesAddress`, `DISABLED_ProcessNodesPubsubs`, `DISABLED_ProcessNodesTransactionsCount`), confirming no working multi-node harness exists (grounds D-35's scope decision)
- `SuperGenius/test/src/CMakeLists.txt`, `SuperGenius/cmake/functions.cmake` (`addtest()` macro) — existing CTest registration convention new render-CI tests should follow

No external ADRs/specs beyond the above — requirements fully captured in REQUIREMENTS.md and this discussion.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `resolve-runners` job in `cmake.yml` — already resolves self-hosted vs. GitHub-hosted fallback per platform; new render-CI steps ride on the same resolved runners, no new runner-selection logic needed.
- `addtest()` CMake macro (`SuperGenius/cmake/functions.cmake:8-27`) — existing CTest registration convention; a GPU-gated test can use this as-is, with the gating logic living inside the test binary (probe-and-skip) rather than at the CMake/CTest level.
- `vulkan_init_concurrency_test.cpp` and `processing_dispatch_test.cpp`'s render tests — already exist from Phases 1/3, already run under the existing `ctest` invocation in every CI matrix job.

### Established Patterns
- Tests that need a "real job definition" fixture (not synthetic minimal JSON) follow `posenet-processing-job.json`'s convention — a full, realistic job file checked into `test/src/<test-dir>/`.
- CI Vulkan setup today is loader-only (`libvulkan-dev` on Linux) — no ICD registration exists yet on any platform; D-32's probe is the first place CI code needs to reason about "is there actually a usable device," not just "is the loader present."

### Integration Points
- `cmake.yml`'s per-platform "Run tests" steps (`ctest . -j -C ...`) are where GPU-gated tests already run — no change needed there; the gating happens inside the test binaries themselves (D-32/D-34), not by CI conditionally invoking `ctest` differently per platform.

</code_context>

<specifics>
## Specific Ideas

No UI/UX-style references — this is CI/build infrastructure. The user provided concrete, load-bearing detail about the self-hosted runner fleet during discussion: `sg-ubuntu-linux` (modern AMD CPUs), `SG-WIN11` (modern AMD/Intel CPUs), `sg-arm-linux` (recent ARM Minisforum box), `gv-OSX-Large` (a Tart VM on a high-end Mac host) — explicitly flagged as "a mixed bag," with GPU availability on any of them **not to be assumed** even where the host hardware sounds capable (e.g. the Mac being "high-end" says nothing about whether the Tart VM guest gets GPU/Metal passthrough). This is the direct grounding for D-32/D-34's probe-don't-assume design.

</specifics>

<deferred>
## Deferred Ideas

- **Software Vulkan ICD tier (lavapipe/SwiftShader)** — considered in depth (platform coverage gaps, mutual exclusivity with MoltenVK, vendoring cost) but explicitly dropped for this phase per D-31, in favor of GPU-probe gating. Revisit if a future milestone needs guaranteed CI coverage on GPU-less runners (the "hardware-independent tier" DETV-03 originally envisioned) rather than probe-and-skip.
- **Multi-node distributed dispatch test** — E2E-01's "distributed processing pipeline" phrase could have meant a genuine multi-node network test; explicitly scoped down to single-node per D-35 since no working multi-node harness exists yet. Revisit if/when `processing_nodes_test.cpp`'s disabled pubsub cases or `processing_multi_test` get resurrected in a future milestone.

</deferred>

---

*Phase: 4-Cross-Platform Build, CI & End-to-End Verification*
*Context gathered: 2026-07-31*
