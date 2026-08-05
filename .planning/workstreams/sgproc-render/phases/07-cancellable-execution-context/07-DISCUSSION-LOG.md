# Phase 07: Cancellable Execution Context - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-08-04
**Phase:** 07-Cancellable Execution Context
**Areas discussed:** Cancellation mechanism, Resource budget enforcement, Progress event design, Safe cleanup & teardown, Migration adapter strategy

---

## Cancellation Mechanism

| Option | Description | Selected |
|--------|-------------|----------|
| Shared token struct | Pass a CancellationToken (atomic bool + stop source) to every StartProcessing(). Processors poll token.IsCancelled() at safe checkpoints. | |
| Callback-based | Register a cancel callback per processor. Async — processor doesn't poll, it gets notified. | ✓ |
| Per-pass deadline only | No explicit cancellation token. Only a deadline — processor checks elapsed time vs deadline. | |

| Option | Description | Selected |
|--------|-------------|----------|
| Per pass (one token per StartProcessing call) | Each pass gets its own token. Natural fit — cancel one pass without affecting others. | |
| Per job (shared across all passes) | One token for the entire job's pass graph. Cancel one pass → cancel all. | ✓ |

| Option | Description | Selected |
|--------|-------------|----------|
| Adapter wraps with no-op | Migration adapter provides default no-op cancel callback. Processors run to completion unaware. | |
| Adapter injects cooperative checkpoints | Adapter wraps long-running operations with cancel checks between stages. | |
| All processors must add cancel support | Update every processor's StartProcessing to accept and honor the token. Adapter handles API shape only. | ✓ |

| Option | Description | Selected |
|--------|-------------|----------|
| Between pipeline stages only | Coarse checkpoints: shader compile → pipeline build → draw → readback. Predictable overhead. | ✓ |
| At every Vulkan/MNN call boundary | Check before every vkCmd*/MNN forward call. Finest granularity but per-call overhead. | |
| You decide per processor type | Render: between stages; MNN: at session boundaries. | |

**User's choice:** Callback-based, per-job token, all processors updated, between pipeline stages only.
**Notes:** Deadline expiry triggers the same cancel callback (unified path).

---

## Resource Budget Enforcement

| Option | Description | Selected |
|--------|-------------|----------|
| In the pass schema/job definition | Each pass declares its budget requirements in the schema. Scheduler sets per-job caps. | ✓ |
| In the ExecutionContext struct only | ProcessingManager constructs budgets from node config. Node-local policy. | |
| Both — schema declares estimates, context enforces caps | Schema for estimates (CapabilityValidator), context for runtime caps. | |

| Option | Description | Selected |
|--------|-------------|----------|
| Pre-execution reject only | CapabilityValidator checks budgets before Process(). No mid-execution enforcement. | ✓ |
| Both — reject upfront + abort mid-execution | Runtime also tracks actual usage and aborts if declared budget is exceeded. | |

| Option | Description | Selected |
|--------|-------------|----------|
| GPU memory + output size + wall-clock deadline | Three budgets covering the critical failure modes. | ✓ |
| Full set — CPU, GPU, RAM, disk, output, deadline | All six EXEC-03 categories. | |

| Option | Description | Selected |
|--------|-------------|----------|
| Cancel via the callback token | Deadline expiry triggers the same cancel callback. Unified path. | ✓ |
| Separate timeout signal | Distinct terminal condition from cancellation. Different error type. | |

**User's choice:** Schema-declared budgets, pre-execution reject only, three budget fields, deadline via cancel callback.
**Notes:** Consistent with Phase 06 D-19 (caller validates, Process() trusts).

---

## Progress Event Design

| Option | Description | Selected |
|--------|-------------|----------|
| Callback in ExecutionContext | Same pattern as cancel callback. Unified API surface. | ✓ |
| Separate observer/event stream | ProcessingManager exposes a progress event stream. Decoupled. | |
| Both — callback for simple cases, stream for complex | Callback default, stream opt-in. | |

| Option | Description | Selected |
|--------|-------------|----------|
| Minimal: pass_id + stage + percent | Pass identifier, stage name, 0-100 float. Backward-compatible. | ✓ |
| Rich: pass_id + stage + completed/total + message | All EXEC-04 fields. More detail but more complexity. | |

| Option | Description | Selected |
|--------|-------------|----------|
| Standardized enum per processor type | Fixed stage names: COMPILE, BUILD_PIPELINE, DRAW, READBACK for Render; LOAD_MODEL, CREATE_SESSION, RUN, READ_OUTPUT for MNN. | ✓ |
| Free-form string per processor | Each processor reports whatever stage names make sense. | |

| Option | Description | Selected |
|--------|-------------|----------|
| Every stage boundary | Fire on every stage transition. 4 events per pass — predictable. | ✓ |
| Throttled — max 10/sec | Cap progress event frequency. | |

**User's choice:** Callback in ExecutionContext, minimal shape, standardized enum, every stage boundary.

---

## Safe Cleanup & Teardown

| Option | Description | Selected |
|--------|-------------|----------|
| Yes — unified teardown stack | Every processor gets PushTeardown/RunTeardown. MNN sessions, buffers, etc. register via PushTeardown. | ✓ |
| No — MNN uses RAII wrappers instead | MNN resources wrapped in unique_ptr with custom deleters. Auto-cleanup on scope exit. | |

| Option | Description | Selected |
|--------|-------------|----------|
| Cancel pending saves, discard partial output | Cancel in-flight SaveASync. Partial output discarded. Clean break. | ✓ |
| Wait for in-flight saves to complete | Let pending saves finish. No partial output, but in-flight writes complete. | |

| Option | Description | Selected |
|--------|-------------|----------|
| Tests with repeat-run leak detection | Run cancel/timeout/failure in loop (N≥10). Track object counts + memory. Assert no growth. | ✓ |
| Valgrind/ASAN integration in CI | Run cancellation tests under ASAN in CI. | |
| Both | Repeat-run + ASAN. | |

| Option | Description | Selected |
|--------|-------------|----------|
| Yes — ProcessingManager wraps Process() in try/catch | Teardown is noexcept-safe. Catches exceptions, calls RunTeardown(). | ✓ |
| No — teardown is cooperative only | Teardown on cancel/timeout/success only. Crashes bypass teardown. | |

**User's choice:** Unified teardown stack, cancel pending saves, repeat-run leak detection (ASAN separately), try/catch guard.
**Notes:** User will separately build ASAN and run tests in a loop.

---

## Migration Adapter Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| New StartProcessing() overload + default wrapper | Add new overload taking ExecutionContext. Old signature delegates to new with default no-op context. | ✓ |
| Wrapper class around each processor | ExecutionContextProcessor wraps a ProcessingProcessor, injects context, delegates. | |

| Option | Description | Selected |
|--------|-------------|----------|
| Temporary — remove after all processors updated | Old signature deprecated and removed in Phase 07. | ✓ |
| Permanent — keep both signatures | Both signatures supported indefinitely for external processors. | |

| Option | Description | Selected |
|--------|-------------|----------|
| Capability flag in processor registration | Boolean supports_checkpointing in registry entry. CapabilityValidator surfaces it. | ✓ |
| Runtime query method on processor | Virtual bool SupportsCheckpointing() on ProcessingProcessor. | |

| Option | Description | Selected |
|--------|-------------|----------|
| Native support — RenderProcessor updated directly | RenderProcessor gets ExecutionContext as first-class citizen. | |
| Same adapter as MNN processors | All processors go through the same migration path. Consistent. | ✓ |

**User's choice:** New overload with default wrapper, temporary adapter, capability flag at registration, same path for all processors.

---

## Claude's Discretion

- Exact C++ type names: `CancellationToken`, `ExecutionContext`, `ProgressEvent`, `RenderStage`, `MNNStage`
- Callback signatures: cancel callback and progress callback function types
- MNN teardown stack integration — where to call `PushTeardown` for MNN session resources
- Schema field names for budget declarations (GPU memory, output size, deadline)
- Budget scope: per-pass vs per-job in schema
- ExecutionContext lifecycle management in ProcessingManager

## Deferred Ideas

- CPU/RAM/disk/network budgets (only GPU memory, output size, deadline in Phase 07)
- Per-pass cancellation tokens (per-job only)
- Mid-execution budget enforcement (pre-execution reject only)
- Progress event throttling (not needed for 4-stage processors)
- Checkpoint serialization and resume (capability flag only)
