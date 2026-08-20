# Phase 18: Build Stability - Context

**Gathered:** 2026-08-20
**Status:** Ready for planning

<domain>
## Phase Boundary

Close BUILD-01: `ProcessingManager::Create()`'s Vulkan capability probe must no longer deadlock `ProcessingDatatypesTest`, `ProcessingDispatchTest`, or `vulkan_init_concurrency_test` when a real Vulkan device is present, via the `VulkanInitMutex` re-entrancy bug tracked in `.planning/todos/pending/2026-08-10-fix-vulkan-capability-probe-deadlock-in-processingmanager-cr.md`. Per ROADMAP.md SC4, the shared `VulkanInitMutex()` coexistence contract (MNN + RenderProcessor sharing one process-wide init lock) must be unchanged in observable behavior for every other caller — only the re-entrancy defect is in scope, not the locking model itself. Scope is `GeniusNetwork/SuperGenius` only (see D-04).

</domain>

<decisions>
## Implementation Decisions

### Central finding — the described bug does not currently reproduce
- **D-01:** Direct reproduction against current HEAD (fresh same-day Debug build, real NVIDIA GeForce RTX 4070 Ti SUPER present) shows none of the three named tests deadlock — confirmed via 4 separate runs (standalone `.exe` invocations and via `ctest -C Debug`, individually and as a set). `ProcessingDatatypesTest` (all subtests), `ProcessingDispatchTest` (12/12), and `vulkan_init_concurrency_test` all pass cleanly.
- **D-02:** Git history in the `SGProcessingManager` submodule shows commit `528a92a` ("Fix hang on OSX", 2026-08-06) already restructured `CapabilityValidator::BuildSnapshot()` (`src/capability/capability_validator.cpp`) to stop holding `VulkanInitMutex()` while calling `ensureVulkanDevice()` — which itself acquires the same mutex internally via `RenderProcessor::InitializeContext()`'s double-checked-locking pattern. This is exactly the self-deadlock pattern BUILD-01 and the pending todo describe. The fix predates both the todo's filing (2026-08-10) and Phase 18's creation (2026-08-17) — the todo was almost certainly filed against stale, not-yet-rebuilt test binaries, and the ROADMAP/REQUIREMENTS carried it forward as still-open without re-verification.
- **D-03 (closure bar):** Treat BUILD-01 as verify-and-close, not a new fix. Planning/execution should: (1) document this evidence trail (already-merged fix + clean repro) as the closure proof, mirroring Phase 13/19's honest-reporting convention; (2) add one regression test that explicitly pins this exact scenario — `ProcessingManager::Create()` with a real Vulkan device present must return without hanging or throwing — ideally timeout-guarded so a future regression fails fast in CI instead of hanging the suite; (3) do not modify `VulkanInitMutex`'s locking model itself (matches ROADMAP SC4, already locked).
- **D-04 (scope):** Keep all code/test changes inside `GeniusNetwork/SuperGenius`. Do not edit files in the separate `GeniusCognitiveSystem` repo as part of this phase — see Deferred Ideas for the cross-repo lead uncovered during this discussion.

### Flaky, unrelated observation — out of scope
- **D-05:** During repro, one of four `ctest` runs of the three-test trio hit a flaky, non-reproducing failure: `processing_dispatch_test` failed with `Failed to open file (Windows): The system cannot find the file specified` (looks like a CWD-relative test-fixture path difference between running the `.exe` directly vs. via `ctest`), followed by an apparent stall before `vulkan_init_concurrency_test`'s result printed. Three subsequent runs (including the identical trio, and `processing_dispatch_test` isolated, and paired with `vulkan_init_concurrency_test`) all passed cleanly — it did not reproduce again. **User decision: out of scope, note only.** Do not investigate or fix in this phase.

### Claude's Discretion
- Evidence bar for closure: Windows-with-real-GPU (the only real-device host exercised in this discussion) is accepted as sufficient; no explicit ask for additional Linux/macOS re-verification was raised, and ROADMAP's SC1-3 don't specify a platform beyond "a real Vulkan device is present."
- Exact form/location of the new regression test (e.g., extending `vulkan_init_concurrency_test.cpp` vs. a new dedicated test) is left to planning/research.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirement & bug tracking
- `.planning/workstreams/sgproc-render/REQUIREMENTS.md` (BUILD-01) — the locked requirement text
- `.planning/todos/pending/2026-08-10-fix-vulkan-capability-probe-deadlock-in-processingmanager-cr.md` — original bug report, repro steps, file/line pointers; treat its "still open" framing as superseded by D-01/D-02 above, but its listed call sites remain the right places to look
- `.planning/workstreams/sgproc-render/STATE.md` (Blockers/Concerns) — carries the same bug forward as "queued for v2.3 Phase 18 (BUILD-01)"

### Code (all in `SuperGenius/SGProcessingManager`)
- `src/capability/capability_validator.cpp:211-235` (`BuildSnapshot`) — already fixed by `528a92a`; the comment at lines 220-226 explains the self-deadlock pattern this phase must not reintroduce
- `src/processingbase/ProcessingManager.cpp:426-513` (`Create()`/`Init()`) — where `BuildSnapshot()` is invoked with the `ensureVulkanDevice` lambda
- `src/processors/processing_processor_render.cpp:58-194` (`RenderProcessor::InitializeContext()`) — double-checked-locking pattern around `VulkanInitMutex()`
- `src/processors/vulkan_gpu_probe.cpp` (`HasUsableVulkanDevice()`) — separate, self-contained `VulkanInitMutex()` call site named in the original todo as a second suspect path; also self-contained and not implicated by the D-01/D-02 finding
- `include/processingbase/vulkan_init_guard.hpp` (`VulkanInitMutex()`) — the shared mutex itself; header comment explicitly states it's process-wide and reacquired per-call, not a run-once primitive — do not change its type/semantics (D-03)

### Cross-repo lead (informational only — not this phase's scope, see Deferred Ideas)
- `GeniusCognitiveSystem/GNUS-NEO-SWARM/test/integration/test_sgprocessing_pipeline.cpp:250-325` — `Fp4UltraFormat_DispatchesToTensorProcessor` / `LlmDataType_JobReachesRegisteredProcessor`, both preemptively `GTEST_SKIP()` when `HasUsableVulkanDevice()` is true, citing this exact todo
- `GeniusCognitiveSystem/GNUS-NEO-SWARM/.planning/workstreams/neoswarm/phases/04-sgprocessing-integration/04-VERIFICATION.md` — documents the skip as *expected* designed behavior on a real-Vulkan-device host, deferred to sgproc-render Phase 18

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `vulkan_init_concurrency_test.cpp` (`SuperGenius/test/src/processing_vulkan_concurrency/`) — existing concurrent-init test harness; likely the natural home for the new regression test from D-03, since it already exercises repeated/concurrent `ProcessingManager::Create()`-adjacent init paths under a real device.
- `sgns::sgprocessing::HasUsableVulkanDevice()` (`vulkan_gpu_probe.cpp`) — existing, working device-presence probe already used by other tests (`capture_smoke_test.cpp`) to gate real-device-only assertions.

### Established Patterns
- Double-checked locking around `VulkanInitMutex()`: check `m_contextInitialized` unlocked, lock, re-check, then do the real work (see `RenderProcessor::InitializeContext()`). Any new code touching `VulkanInitMutex()` should follow this same shape.
- Honest-reporting convention (Phase 13/19): when a fix's real-world status is uncertain or already resolved by prior work, document the evidence trail explicitly rather than silently asserting "fixed" or "broken."

### Integration Points
- `CapabilityValidator::BuildSnapshot()` is called exactly once per `ProcessingManager::Init()`, unconditionally, regardless of which `DataType`/`PassType` the submitted job actually needs — so any test that reaches `ProcessingManager::Create()` at all exercises this code path, not just render-specific tests.

</code_context>

<specifics>
## Specific Ideas

No specific UI/behavior requests — this is a backend correctness/verification phase. The user's driving concern, surfaced mid-discussion, is that a downstream consumer project is currently working around this bug by skipping tests; they want confidence this is genuinely closed on the SuperGenius side (D-01-D-03), while explicitly keeping this phase's edits scoped to SuperGenius (D-04).

</specifics>

<deferred>
## Deferred Ideas

- **Cross-repo NEO-SWARM stale skip-guard:** `GeniusCognitiveSystem/GNUS-NEO-SWARM/test/integration/test_sgprocessing_pipeline.cpp`'s `Fp4UltraFormat_DispatchesToTensorProcessor` and `LlmDataType_JobReachesRegisteredProcessor` tests skip whenever a real Vulkan device is present, specifically to dodge this bug (added 2026-08-18, per their own 04-VERIFICATION.md, as a *designed deferral* to this phase — not an independent fresh repro of a hang in that exact binary). Given D-01/D-02's finding, this guard is very likely stale now and could be removed so those two tests actually execute and pass on a real-device host. User decided this phase stays SuperGenius-only (D-04); flagging this as a strong, evidence-backed lead for a future todo/phase in the `GeniusCognitiveSystem`/`neoswarm` workstream to pick up and verify (their own build was separately reported as blocked by an unrelated `get_third_party_dir()` CMake configure issue in 04-VERIFICATION.md — that would need checking too before this lead can be closed out).
- **Flaky `processing_dispatch_test` CWD-relative file failure (D-05):** noted, not investigated. If it recurs, it looks like a test-fixture path resolution issue (differs between direct `.exe` invocation and `ctest`), unrelated to `VulkanInitMutex`.

### Reviewed Todos (not folded)
None — `todo.match-phase` returned zero matches for Phase 18 at discussion time.

</deferred>

---

*Phase: 18-Build Stability*
*Context gathered: 2026-08-20*
