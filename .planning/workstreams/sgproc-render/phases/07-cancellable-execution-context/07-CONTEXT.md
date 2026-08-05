# Phase 07: Cancellable Execution Context - Context

**Gathered:** 2026-08-04
**Status:** Ready for planning

<domain>
## Phase Boundary

Add cooperative cancellation, per-pass deadlines, resource budgets, structured progress events, checkpoint support, and safe cleanup to every processor in SGProcessingManager — through a new `ExecutionContext` that wraps each `ProcessingProcessor::StartProcessing()` call. All 14 MNN processors and the `RenderProcessor` receive the new API via a migration adapter that is removed before the phase ships. Existing processors remain functional throughout.

**Depends on:** Phase 06 (CAP — `CapabilityValidator` pre-execution gate; D-19 caller-responsibility model).

</domain>

<decisions>
## Implementation Decisions

### Cancellation Mechanism (EXEC-01, EXEC-05)

- **D-01:** Callback-based cancellation — each processor registers a cancel callback via `ExecutionContext` and is notified asynchronously when cancellation is requested. No polling of atomic flags; zero-latency response.
- **D-02:** Per-job token — one cancellation token is shared across all passes in a job's pass graph. Cancelling any pass cancels the entire job. Simpler lifecycle than per-pass tokens.
- **D-03:** All processors must add cancel support — every `StartProcessing()` is updated to accept and honor the cancel callback. The migration adapter handles API shape compatibility only (old signature → new signature), not behavioral no-ops.
- **D-04:** Cancel check granularity — processors check for cancellation between pipeline stages only (coarse checkpoints). Render: between shader compile → pipeline build → draw → readback. MNN: between session create → run → output read. No per-API-call overhead.
- **D-05:** Deadline expiry triggers the same cancel callback as explicit cancellation — a unified terminal path. The processor returns a distinct error code so the caller can distinguish "user cancelled" from "deadline exceeded" in logs/metrics, but cleanup and teardown are identical.

### Resource Budget Enforcement (EXEC-02, EXEC-03)

- **D-06:** Budgets are declared in the pass schema/job definition — each pass carries its own resource estimates. Visible to the scheduler and `CapabilityValidator` before claiming work.
- **D-07:** Pre-execution reject only — `CapabilityValidator` checks declared budgets against node resources. If a pass declares it needs 8 GB VRAM and the node has 4 GB, the job is rejected before downloading inputs. `Process()` trusts the caller validated (extends Phase 06 D-19).
- **D-08:** Three budget fields in the schema: estimated GPU memory (bytes), maximum output artifact size (bytes), and per-pass wall-clock deadline (milliseconds). Covers the critical failure modes; CPU/RAM/disk/network budgets are deferred.
- **D-09:** Deadline expiry uses the unified cancel path (D-05) — no separate timeout signal. When the deadline fires, the cancel callback is invoked and the processor returns a timeout-distinct error code.

### Progress Event Design (EXEC-04)

- **D-10:** Progress callback in `ExecutionContext` — same callback-registration pattern as the cancel callback. Processors call it at stage boundaries. Unified API surface.
- **D-11:** Minimal event shape: `pass_id` + `stage_name` + `percent` (0–100 float). Replaces the current single atomic float percentage. Sufficient for scheduler observability without requiring completed/total work counts.
- **D-12:** Standardized stage enum per processor type — not free-form strings. `RenderProcessor` stages: `COMPILE`, `BUILD_PIPELINE`, `DRAW`, `READBACK`. MNN stages: `LOAD_MODEL`, `CREATE_SESSION`, `RUN`, `READ_OUTPUT`. Comparable across jobs of the same type.
- **D-13:** Fire on every stage boundary — no throttling. Current processor workloads have 4 stages each; no risk of event storms.

### Safe Cleanup & Teardown (EXEC-06)

- **D-14:** Unified `PushTeardown`/`RunTeardown` stack for ALL processors — MNN processors adopt the same reverse-order LIFO teardown pattern already in `RenderProcessor`. On cancel, timeout, failure, or success, `RunTeardown()` fires in reverse order. MNN sessions, Vulkan buffers, images, pipelines, command pools all register via `PushTeardown`.
- **D-15:** Cancel pending `FileManager::SaveASync` calls — discard partial output on any terminal condition. No partial artifact is published. Clean break, no filesystem corruption risk.
- **D-16:** Verification via repeat-run leak detection in tests — run cancel/timeout/failure scenarios in a loop (N ≥ 10 iterations), track Vulkan object counts + MNN session counts + memory, assert no growth across iterations. ASAN/Valgrind run separately by the developer.
- **D-17:** `ProcessingManager` wraps `Process()` in try/catch — `RunTeardown()` is called in the catch block. Teardown functions must be noexcept-safe since stack unwinding may leave Vulkan objects in an unknown state.

### Migration Adapter (EXEC-07)

- **D-18:** New `StartProcessing()` overload taking `ExecutionContext` — the old signature (no context) delegates to the new one with a default no-op `ExecutionContext`. All 14 MNN processors + `RenderProcessor` override the new overload. Old callers don't break during migration.
- **D-19:** Temporary adapter — the old `StartProcessing()` signature is deprecated and removed before Phase 07 ships. Not a permanent API feature.
- **D-20:** Checkpoint support declared via capability flag at processor registration time — a boolean `supports_checkpointing` in the executor registry entry. `CapabilityValidator` surfaces this. No runtime virtual method query needed.
- **D-21:** All processors (MNN inference + `RenderProcessor`) go through the same adapter path — consistent migration, no special-casing. `RenderProcessor` is not given native `ExecutionContext` support ahead of other processors.

### Claude's Discretion

- Exact C++ type names for `CancellationToken`, `ExecutionContext`, `ProgressEvent`, and the stage enums (`RenderStage`, `MNNStage`).
- Exact callback signatures — cancel callback and progress callback function types.
- How the teardown stack integrates with MNN processors (where to call `PushTeardown` for MNN session resources).
- Exact schema field names for the three budget declarations (GPU memory, output size, deadline).
- Whether budgets are declared per-pass or per-job in the schema.
- How `ProcessingManager` constructs and manages the `ExecutionContext` lifecycle (one per job, owned by `ProcessingManager`).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements & Roadmap
- `.planning/workstreams/sgproc-render/REQUIREMENTS.md` — EXEC-01..07 locked requirements for this phase
- `.planning/workstreams/sgproc-render/ROADMAP.md` — Phase 07 goal, success criteria, and requirement traceability

### Prior Phase Context
- `.planning/workstreams/sgproc-render/phases/06-capability-validation-foundation/06-CONTEXT.md` — D-01/D-04 (internally constructed by ProcessingManager), D-03 (async callback pattern), D-19 (caller-responsibility — validate before Process()), D-09/D-10 (startup snapshot + VkPhysicalDevice reuse), D-14 (critical Vulkan limits), D-15/D-16 (GPU/disk estimation). Phase 07's budget enforcement (D-07) extends D-19.

### Source of Truth
- `SuperGenius/SGProcessingManager/include/processors/processing_processor.hpp` — `ProcessingProcessor` base class and `ProcessingResult` struct — the interface being extended with `ExecutionContext`
- `SuperGenius/SGProcessingManager/include/processors/processing_processor_render.hpp` — `RenderProcessor::PushTeardown`/`RunTeardown` — the teardown stack pattern being generalized (D-14)
- `SuperGenius/SGProcessingManager/src/processing_manager.cpp` — `Process()` dispatch and `CheckProcessValidity()` — the code paths D-17 wraps with try/catch
- `SuperGenius/SGProcessingManager/include/capability/capability_validator.hpp` — `CanExecute()` and `CanExecuteCallback` patterns — the callback style D-01/D-10 follow
- `SuperGenius/SGProcessingManager/include/capability/capability_types.hpp` — `CanExecuteResult` struct — the structured-result convention for new types
- `SuperGenius/SGProcessingManager/include/processingbase/vulkan_init_guard.hpp` — `VulkanInitMutex()` — any Vulkan resource creation in new processor paths must acquire this

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`RenderProcessor::PushTeardown`/`RunTeardown`** — existing reverse-order LIFO teardown stack. Generalized to all processors via D-14. MNN processors will register session cleanup, buffer frees, and output artifact teardown via the same mechanism.
- **`CapabilityValidator` callback pattern** — `CanExecute(Pass, CanExecuteCallback)` async callback convention. The cancel and progress callbacks in `ExecutionContext` follow the same style.
- **`ProcessingResult` error field** (Phase 3 D-25..D-28) — per-stage enum + message string. Cancel/timeout/budget-exceeded error codes follow the same structured-error pattern.
- **`VulkanInitMutex`** — shared mutex for Vulkan resource creation. Any processor that creates Vulkan objects during `StartProcessing()` must acquire this mutex. Teardown functions also acquire it when destroying Vulkan objects.
- **14 MNN processors** — all on Vulkan backend after Phase 01.1 MIGR-01. Each has a `StartProcessing()` that creates an MNN session via `createSession()` and runs inference. The teardown stack (D-14) gives each one structured cleanup of MNN sessions.

### Established Patterns
- **Async callback pattern** — `ProcessingManager::Process()` and `CanExecute()` use `std::function` callbacks. `ExecutionContext`'s cancel and progress callbacks follow the same convention.
- **Registry-based processor registration** — Phase 1 DISP-02 established a `PassType`-keyed factory map. D-20 adds a `supports_checkpointing` boolean to each executor's registry entry.
- **Schema-driven configuration** — Phase 2 SCHEMA-01..05 established schema-as-config. D-06/D-08 add three budget fields to the existing pass schema.
- **Pre-execution validation gate** — Phase 06 CAP-01..06 established `CapabilityValidator` as the gate before `Process()`. D-07 extends this with budget checks.

### Integration Points
- **`ProcessingManager::Process()`** — the dispatch point where `ExecutionContext` is constructed and injected into each processor's `StartProcessing()`. Also the try/catch boundary for D-17.
- **`ProcessingProcessor::StartProcessing()`** — the base class method being overloaded with the new `ExecutionContext`-taking signature (D-18).
- **`FileManager::SaveASync`** — pending saves are cancelled on terminal conditions (D-15).
- **Processor factory maps** — both the `DataType`-keyed MNN map and the `PassType`-keyed render map. The new `StartProcessing()` overload must be callable through both.

</code_context>

<deferred>
## Deferred Ideas

- **CPU/RAM/disk/network budgets** — only GPU memory, output size, and deadline are scoped for Phase 07 (D-08). Other EXEC-03 budget categories are deferred.
- **Per-pass cancellation tokens** — per-job token is simpler (D-02). Per-pass granularity deferred until multi-pass job graphs with independent pass cancellation are needed.
- **Mid-execution budget enforcement** — pre-execution reject only (D-07). Runtime tracking and mid-execution abort on budget exceeded is deferred.
- **Progress event throttling** — not needed for current 4-stage processors (D-13). Deferred until processors with many micro-stages exist.
- **Checkpoint/partial-result callbacks** — capability flag only (D-20). Actual checkpoint serialization and resume is deferred to a future phase.
</deferred>

---

*Phase: 07-Cancellable Execution Context*
*Context gathered: 2026-08-04*
