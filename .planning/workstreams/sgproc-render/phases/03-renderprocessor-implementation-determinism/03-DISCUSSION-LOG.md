# Phase 3: RenderProcessor Implementation & Determinism - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-07-31
**Phase:** 3-RenderProcessor Implementation & Determinism
**Areas discussed:** Vulkan memory allocation strategy, Resource lifecycle across repeated runs, Error surfacing mechanism (RENDER-09), Push-constant fallback threshold (RENDER-05)

---

## Vulkan Memory Allocation Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Vendor VMA | Vulkan Memory Allocator (GPUOpen, MIT) — same vendoring precedent as vk-bootstrap/shaderc | |
| Hand-roll manual vkAllocateMemory | Zero new vendoring, most literal reading of issue #7's minimalism | ✓ |

**User's choice:** Hand-roll manual vkAllocateMemory.

| Option | Description | Selected |
|--------|-------------|----------|
| Dedicated allocation per resource | One vkAllocateMemory per buffer/image | ✓ |
| Shared block, manual sub-allocation | Fewer allocation calls, manual offset/alignment bookkeeping | |

**User's choice:** Dedicated allocation per resource.

| Option | Description | Selected |
|--------|-------------|----------|
| HOST_VISIBLE \| HOST_COHERENT | No manual flush/invalidate needed | ✓ |
| HOST_VISIBLE non-coherent + manual flush | Marginally faster on some hardware, manual flush required | |

**User's choice:** HOST_VISIBLE | HOST_COHERENT, for the readback staging buffer and host-visible uniform buffers.

| Option | Description | Selected |
|--------|-------------|----------|
| HOST_VISIBLE direct | One buffer, CPU writes directly, no staging upload | ✓ |
| DEVICE_LOCAL + staging upload | Best GPU-read bandwidth, extra copy + barrier | |

**User's choice:** HOST_VISIBLE direct, for vertex/index/uniform input buffers.

**Notes:** All four sub-questions resolved toward the simplest/most-minimal option, consistent with this being a discrete batch job (not a real-time render loop) and issue #7's "no new GPU backend, minimal duplicate setup" framing.

---

## Resource Lifecycle Across Repeated Runs

| Option | Description | Selected |
|--------|-------------|----------|
| Fresh build + full teardown per call | Rebuild pipeline/framebuffer/buffers every StartProcessing() call | ✓ |
| Cache/reuse pipeline + framebuffer across jobs | Faster for repeated jobs, adds cache-key/invalidation logic | |

**User's choice:** Fresh build + full teardown per call.

| Option | Description | Selected |
|--------|-------------|----------|
| Synchronous wait + destroy before return | Simplest teardown story | ✓ (after clarification) |
| Async/deferred cleanup after hash readback | Avoids blocking the calling thread, adds deletion-queue complexity | |

**User's choice:** Initially raised a concern via free text: "The SDK could in fact be attached to a game that is running vulkan, so i'm not sure waiting for idle is a good idea." Claude clarified that RenderProcessor uses its own fully independent VkDevice/VkQueue (Phase 1, CTX-01), so `vkDeviceWaitIdle` cannot block a separate host VkDevice at the Vulkan API level — the only shared-resource risk Phase 1 addressed was instance/device *creation-time* contention (CTX-02's mutex), not steady-state submission. After this was walked through, user confirmed synchronous wait + destroy is acceptable.
**Notes:** This exchange is recorded in full in CONTEXT.md's D-23 — flagged so planner/researcher don't silently reopen it as an unresolved question.

| Option | Description | Selected |
|--------|-------------|----------|
| Always destroy partial state, even on failure | No leaks even on error paths | ✓ |
| Acceptable to leak on failure for v1 | Simpler failure-path code, real leak risk over node lifetime | |

**User's choice:** Always destroy partial state, even on failure.

---

## Error Surfacing Mechanism (RENDER-09)

| Option | Description | Selected |
|--------|-------------|----------|
| New error field on ProcessingResult | Minimal blast radius, no signature/exception-handling changes | ✓ |
| Throw C++ exceptions | Matches stated coding-standard note, but no existing call site expects exceptions from StartProcessing() | |

**User's choice:** New error field on ProcessingResult.

| Option | Description | Selected |
|--------|-------------|----------|
| Per-stage enum values | Distinguishable by type, matches "clear per-failure-point messages" | ✓ |
| Single generic code + message string | Less enum surface, weaker distinguishability | |

**User's choice:** Per-stage enum values.

| Option | Description | Selected |
|--------|-------------|----------|
| Skip save/hash on error | Prevents a failed job from producing a fake all-zero-hash "success" | ✓ |
| Flow through unchanged (current MNN behavior) | Simplest change, preserves existing latent bug | |

**User's choice:** Skip save/hash on error.

| Option | Description | Selected |
|--------|-------------|----------|
| Render-pass path only (stays in scope) | Doesn't touch existing MNN dispatch code | |
| Fix both render and MNN paths now | Broadens this phase's blast radius to also fix MNN's same latent bug | ✓ |

**User's choice:** Fix both render and MNN paths now. Explicitly chosen as a deliberate scope-broadening decision — user was shown the tradeoff (touching already-shipped MNN code vs. staying strictly in RENDER-09's scope) and chose to fix both since the dispatch logic is being touched anyway.

---

## Push-Constant Fallback Threshold (RENDER-05)

| Option | Description | Selected |
|--------|-------------|----------|
| Fixed conservative 128 bytes | Spec-guaranteed minimum, same code path on every node | ✓ |
| Adaptive — query actual device limit at runtime | Better hardware utilization, path can vary per-node | |

**User's choice:** Fixed conservative 128 bytes.

| Option | Description | Selected |
|--------|-------------|----------|
| All-or-nothing fallback | One binary per-job decision, simpler pipeline-layout logic | ✓ |
| Per-uniform split (partial spill) | Maximizes push-constant usage, data-dependent pipeline layout | |

**User's choice:** All-or-nothing fallback.

---

## Claude's Discretion

- Exact enum member names/values for the new per-stage error type, and the exact shape of the new `ProcessingResult` error field (struct vs. optional, etc.)
- Exact byte layout/packing order of uniforms within push-constant/UBO blocks
- Exact `VkResult`-to-message formatting and descriptor-set-layout/pipeline-layout code path details for the fallback case
- Whether the MNN-path error-handling fix (D-28) lands in this phase's plan set directly or via a small shared/preparatory plan

## Deferred Ideas

None — discussion stayed within Phase 3 scope. D-28 (broadening the error-handling fix to the MNN dispatch path) was a deliberate, explicit scope decision by the user, not a deferred idea.
