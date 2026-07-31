# Phase 3: RenderProcessor Implementation & Determinism - Context

**Gathered:** 2026-07-31
**Status:** Ready for planning

<domain>
## Phase Boundary

`RenderProcessor` (currently a stub in `processing_processor_render.cpp` that only initializes the headless Vulkan context from Phase 1 and returns a zero hash) actually executes a schema-declared render pass: build the vertex+fragment pipeline from validated SPIR-V, upload vertex/index/uniform data, draw to an offscreen depth-tested framebuffer, read back the result, and feed it through the existing `pass_io_binding` output → `data_transform` → `ProcessingResult` → `FileManager::SaveASync` → hash path. The same job definition must produce a bit-exact matching output hash across N≥10 repeated runs on the same node, via architectural guards (explicit clears, fixed sample count, fixed shader precision, no unordered parallel reduction), not incidental behavior. No CI wiring or cross-platform verification (Phase 4). Requirements: RENDER-01..09, DETV-01, DETV-02.

</domain>

<decisions>
## Implementation Decisions

### Vulkan Memory Allocation Strategy
- **D-18:** Hand-rolled manual `vkAllocateMemory` — no vendored memory allocator (VMA was considered and explicitly rejected). Consistent with issue #7's minimalism spirit and the small number of allocation sites in this phase (~5-8).
- **D-19:** Each buffer/image gets its **own dedicated `VkDeviceMemory` allocation** — no shared-block manual sub-allocation. Allocation volume is trivial for a discrete batch job; dedicated allocations avoid the offset/alignment bookkeeping bug class that motivated considering VMA in the first place.
- **D-20:** The readback staging buffer (and any host-visible uniform buffers) use **`HOST_VISIBLE | HOST_COHERENT`** memory — no manual `vkFlushMappedMemoryRanges`/`vkInvalidateMappedMemoryRanges`. A missed or misaligned manual flush is a direct, silent threat to DETV-01's bit-exact hash guarantee; coherent memory removes that failure mode entirely and is universally supported.
- **D-21:** Vertex/index buffers and descriptor-set uniform buffers use **`HOST_VISIBLE` direct write** — no staging buffer + device-local upload path. This is a discrete batch job (submit-once-return-hash, not a real-time render loop), so the device-local bandwidth upside doesn't pay for the extra buffer/copy/barrier.

### Resource Lifecycle Across Repeated Runs
- **D-22:** **Fresh build + full teardown per `StartProcessing()` call.** Pipeline, framebuffer, and all per-job buffers/images are built from scratch and destroyed every call — no cross-job caching/reuse of Vulkan objects. Zero shared mutable GPU state between jobs, matching Phase 1's D-06 lazy-init philosophy (only the base `VkInstance`/`VkDevice`/`VkQueue` persists) and giving the simplest possible story for DETV-01's determinism claim.
- **D-23:** `StartProcessing()` performs a **synchronous wait (`vkDeviceWaitIdle`) and destroys all per-job Vulkan objects before returning** — no deferred/async cleanup queue.
  - **Explicitly discussed concern:** the user raised that GeniusSDK may be embedded in a host game that is *also* using Vulkan, and worried a synchronous wait could stall the host's rendering. **Resolved:** `RenderProcessor` uses its own fully independent `VkInstance`/`VkDevice`/`VkQueue` (locked in Phase 1, CTX-01) — `vkDeviceWaitIdle` only synchronizes on RenderProcessor's own device and cannot block a separate host `VkDevice`/queue at the Vulkan API level. The only real coexistence risk is instance/device *creation-time* contention, already handled by Phase 1's shared `VulkanInitMutex` (CTX-02). Physical-GPU hardware-scheduling contention between a host game and this node's render jobs is a real but orthogonal concern that exists regardless of sync-vs-async cleanup. After this was walked through, the user confirmed synchronous wait+destroy is acceptable. **Planner/researcher: do not silently revisit this as an open question — it was explicitly raised and resolved.**
- **D-24:** On partial failure mid-build (e.g., a later shader stage or pipeline creation fails after earlier objects were already created), RenderProcessor **always destroys whatever was already created** before returning the error — never leaks on the failure path. Matters for a long-running node that may receive repeated malformed jobs over its process lifetime.

### Error Surfacing Mechanism (RENDER-09)
- **Context:** `ProcessingResult` (`processing_processor.hpp:19-25`) has **no error/status field today**. MNN processors currently return a default-constructed `ProcessingResult{}` (hash of zeros) on failure with zero detail (see `processing_processor_mnn_image.cpp:47,82`). RENDER-09's "structured `ProcessingManager::Error` values" do not exist yet — this phase must introduce them.
- **D-25:** Add a **new error field to `ProcessingResult`** (not exceptions). Minimal blast radius — no `StartProcessing()` signature change, no new cross-cutting exception-handling plumbing in `ProcessingManager::Process()`'s dispatch call site, and other processors can adopt it incrementally.
- **D-26:** The error type uses **per-stage enum values** (e.g. pipeline creation, buffer/image allocation, shader module creation, draw submission, readback — exact naming left to planner), each carrying a message string with the specific `VkResult`/context. Matches RENDER-09's "clear per-failure-point messages" wording — callers/logs can distinguish failure stages by type, not just by string-matching a generic message.
- **D-27:** `ProcessingManager::Process()`'s dispatch logic **checks the error field and skips `FileManager::SaveASync`/the hash path entirely on failure** — it must not let a failed render result flow through as if it were a real, valid all-zero-hash "success" the way MNN processors currently do.
- **D-28 (scope, explicitly broadened by user):** This new error-checking gate is **applied to both the render-pass dispatch path AND retroactively to the existing MNN dispatch path** in `ProcessingManager::Process()`, fixing the same latent all-zero-hash-on-failure bug there too. The user was shown this as a scope-broadening choice (existing MNN paths are working, if imperfect, code outside RENDER-09's literal scope) and explicitly chose to fix both since the dispatch logic is being touched anyway. **This is a deliberate, confirmed scope decision — not scope creep to flag or redirect.**

### Push-Constant Fallback Threshold (RENDER-05)
- **D-29:** Push-constant fallback threshold is a **fixed, conservative 128 bytes** (the Vulkan spec-guaranteed minimum `maxPushConstantsSize`) — not an adaptive query of the actual device's limit. The same job definition takes the exact same code path (push-constant vs. descriptor-set) on every node in the network regardless of which node's hardware picks it up.
- **D-30:** The fallback is **all-or-nothing per job**: if a job's total packed uniform size is ≤128 bytes, everything goes in push constants; if it exceeds 128 bytes, *all* uniforms for that job move together into a single descriptor-set UBO. No per-uniform partial spill — avoids making the pipeline layout/descriptor-set shape data-dependent on which specific uniforms happened to fit.

### Claude's Discretion
- Exact enum member names/values for the new per-stage error type (D-26) and the new `ProcessingResult` error field's exact shape (struct vs. `std::optional<Error>` vs. similar) — left to planner/researcher as long as D-25/D-26/D-27 are honored.
- Exact byte layout/packing order of uniforms within the push-constant block or descriptor-set UBO (e.g., declaration order vs. a canonical sort) — mechanical detail, no vision-level ambiguity raised.
- Exact `VkResult`-to-message-string formatting, and the precise shape of the descriptor-set-layout/pipeline-layout code path used in the D-30 fallback case.
- Whether the MNN-path fix from D-28 is done as part of this phase's plan set or requires a small preparatory/shared plan — sequencing detail, not a vision decision.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements & Roadmap
- `.planning/workstreams/sgproc-render/REQUIREMENTS.md` — RENDER-01..09, DETV-01, DETV-02 locked requirements for this phase
- `.planning/workstreams/sgproc-render/ROADMAP.md` — Phase 3 success criteria (very prescriptive — most low-level mechanics are already spelled out at the requirements level, not just discovered here)

### Prior Phase Context
- `.planning/workstreams/sgproc-render/phases/01-vulkan-foundation-dispatch-plumbing/01-CONTEXT.md` — D-06 (lazy per-job Vulkan context init, base instance/device/queue persist), CTX-01 (RenderProcessor's own independent VkInstance/VkDevice — load-bearing for D-23's coexistence resolution), CTX-02 (shared `VulkanInitMutex` for concurrent init only)
- `.planning/workstreams/sgproc-render/phases/02-schema-extension-shader-spir-v-validation-pipeline/02-CONTEXT.md` — D-11/D-12 (shader stages array + shared top-level uniforms map, informs D-29/D-30's push-constant packing scope), D-13/D-14 (pipeline_state enum surface, feeds RENDER-04), D-16 Amendment (`vertex_buffer`/`vertex_layout` binding shape RenderProcessor must consume)

### Source of Truth (current state, pre-this-phase)
- `SuperGenius/SGProcessingManager/include/processors/processing_processor_render.hpp` and `src/processors/processing_processor_render.cpp` — the exact stub this phase fills in. `InitializeContext()` (headless Vulkan context, Phase 1) already exists and works; `StartProcessing()` currently only calls it and returns a zero hash — this is the entire surface of Phase 3's work.
- `SuperGenius/SGProcessingManager/include/processors/processing_processor.hpp:19-25` — `ProcessingResult` struct, gaining the new error field (D-25)
- `SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_image.cpp:47,82` (and the sibling `_mnn_string`/`_mnn_volume` files) — the existing all-zero-hash-on-failure pattern D-28 also fixes
- `SuperGenius/SGProcessingManager/generated/RenderShaderConfig.hpp`, `RenderShaderUniform.hpp`, `RenderTarget.hpp` — quicktype-generated headers from Phase 2's schema extension, the actual typed data RenderProcessor consumes
- `SuperGenius/SGProcessingManager/include/processingbase/vulkan_init_guard.hpp` — `VulkanInitMutex()`, already used by `InitializeContext()` and relevant to D-23's coexistence discussion

No external ADRs/specs beyond the above — requirements fully captured in REQUIREMENTS.md and this discussion.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `RenderProcessor::InitializeContext()` (`processing_processor_render.cpp:29-118`) — already builds the headless `VkInstance`/`VkPhysicalDevice`/`VkDevice`/`VkQueue` via vk-bootstrap with deterministic device selection (CTX-03) and the shared init mutex. This phase only adds per-job pipeline/buffer/draw/readback logic on top — the context bootstrap itself is done.
- Generated schema headers (`RenderShaderConfig.hpp`, `RenderTarget.hpp`, `VertexBuffer.hpp`, `PipelineState.hpp` or equivalent from Phase 2) — fully typed, quicktype-regenerated accessors for everything a render pass declares; no hand-parsing of JSON needed.
- `pass_io_binding`'s existing `source:`/`target:` prefix-notation resolution mechanism — already used elsewhere in `ProcessingManager` to resolve input/output/internal/parameter buffers; RenderProcessor's vertex/index/uniform buffer inputs and `texture2D` output should resolve through this same existing mechanism (RENDER-02, RENDER-06), not a new one.

### Established Patterns
- `ProcessingResult` (`processing_processor.hpp:19-25`) — `hash` + `output_buffers` + `output_locations`. Gains a new error field this phase (D-25); no other structural change needed.
- MNN processors' current failure convention (return `ProcessingResult{}`, hash of zeros, no detail) is the exact anti-pattern D-25..D-28 replace — both for the new render path and, per D-28, retroactively for MNN's own dispatch path.

### Integration Points
- `ProcessingManager::Process()`'s render-pass dispatch branch (added in Phase 1's DISP-02, a separate `PassType`-keyed factory map) — this is where D-27/D-28's error-field check and skip-save-on-error gate get added, for both the render and MNN dispatch paths.
- `ProcessingManager::CheckProcessValidity()` and `GetCidForProc()` (extended in Phase 2's 02-04 plan with `ShaderCompiler` wiring) — RenderProcessor receives already-compiled-and-validated SPIR-V by the time `StartProcessing()` runs; it does not do any shader compilation or `spirv-val` itself.

</code_context>

<specifics>
## Specific Ideas

No UI/UX-style references — this is Vulkan rendering/backend infrastructure. The concrete, grounding specifics from discussion (memory allocation policy, lifecycle/teardown timing, error enum shape, push-constant threshold) are recorded above in `<decisions>`.

One important piece of domain context surfaced during discussion: **GeniusSDK may be embedded inside a host application (e.g. a game) that runs its own, separate Vulkan rendering.** RenderProcessor's coexistence-safety story (own independent VkInstance/VkDevice from Phase 1, CTX-01) needs to hold up not just against MNN's Vulkan usage but against an arbitrary host application's Vulkan usage too. This was resolved for the synchronous-teardown question (D-23) but is worth keeping in mind generally for this phase and Phase 4's end-to-end verification.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within Phase 3 scope. (D-28's broadening to also fix the MNN dispatch path's error handling is a deliberate scope decision the user made explicitly, not a deferred idea — see `<decisions>`.)

</deferred>

---

*Phase: 3-RenderProcessor Implementation & Determinism*
*Context gathered: 2026-07-31*
