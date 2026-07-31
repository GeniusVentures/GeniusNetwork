# Phase 3: RenderProcessor Implementation & Determinism - Research

**Researched:** 2026-07-31
**Domain:** Hand-rolled Vulkan graphics pipeline execution (offscreen, headless) inside an existing C++ distributed-processing node
**Confidence:** MEDIUM-HIGH (Vulkan API mechanics: HIGH/well-trodden; this-codebase's actual data-plumbing gaps: HIGH, empirically grepped; determinism guard sufficiency: MEDIUM, architectural not empirically proven until DETV-01's repeat-run test executes)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Vulkan Memory Allocation Strategy**
- D-18: Hand-rolled manual `vkAllocateMemory` — no vendored memory allocator (VMA explicitly rejected).
- D-19: Each buffer/image gets its own dedicated `VkDeviceMemory` allocation — no shared-block sub-allocation.
- D-20: Readback staging buffer (and any host-visible uniform buffers) use `HOST_VISIBLE | HOST_COHERENT` memory — no manual flush/invalidate calls.
- D-21: Vertex/index buffers and descriptor-set uniform buffers use `HOST_VISIBLE` direct write — no staging buffer + device-local upload path.

**Resource Lifecycle Across Repeated Runs**
- D-22: Fresh build + full teardown per `StartProcessing()` call — no cross-job caching/reuse of pipeline/framebuffer/per-job buffers/images.
- D-23: `StartProcessing()` performs a synchronous `vkDeviceWaitIdle` and destroys all per-job Vulkan objects before returning — no deferred/async cleanup. (Coexistence-with-host-app concern explicitly raised and resolved: RenderProcessor's own independent `VkInstance`/`VkDevice`/`VkQueue` from Phase 1 CTX-01 means this wait cannot block a separate host `VkDevice`. Do not re-litigate.)
- D-24: On partial failure mid-build, always destroy whatever was already created before returning the error — never leak on the failure path.

**Error Surfacing Mechanism (RENDER-09)**
- D-25: Add a new error field to `ProcessingResult` (not exceptions) — no `StartProcessing()` signature change.
- D-26: Error type uses per-stage enum values (pipeline creation, buffer/image allocation, shader module creation, draw submission, readback, etc.), each carrying a message string with the specific `VkResult`/context.
- D-27: `ProcessingManager::Process()`'s dispatch logic checks the error field and skips `FileManager::SaveASync`/the hash path entirely on failure.
- D-28: This error-checking gate is applied to BOTH the render-pass dispatch path AND retroactively to the existing MNN dispatch path (deliberate, confirmed scope decision — not scope creep).

**Push-Constant Fallback Threshold (RENDER-05)**
- D-29: Fixed, conservative 128-byte threshold (Vulkan spec-guaranteed minimum `maxPushConstantsSize`) — not an adaptive per-device query.
- D-30: All-or-nothing per job: ≤128 bytes total → everything in push constants; >128 bytes → all uniforms move together into a single descriptor-set UBO. No per-uniform partial spill.

### Claude's Discretion
- Exact enum member names/values for the new per-stage error type (D-26) and `ProcessingResult`'s new error field shape (struct vs. `std::optional<Error>` vs. similar).
- Exact byte layout/packing order of uniforms within the push-constant block or descriptor-set UBO (declaration order vs. canonical sort).
- Exact `VkResult`-to-message-string formatting, and the precise descriptor-set-layout/pipeline-layout code path for the D-30 fallback case.
- Whether the D-28 MNN-path fix is done as part of this phase's plan set or a small preparatory/shared plan.

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within Phase 3 scope. (D-28's broadening to also fix the MNN dispatch path is a deliberate scope decision, not a deferred idea.)
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| RENDER-01 | Build vertex+fragment pipeline from schema-declared, validated SPIR-V | See Architecture Patterns §Pipeline Creation, Code Examples §1; wire-format gap re: entry points documented in Pitfall 6 |
| RENDER-02 | Upload vertex/index buffer data from `pass_io_binding`-resolved inputs via direct Vulkan buffer APIs | See Pitfall 1 (data-plumbing gap — the "existing resolution mechanism" referenced in CONTEXT.md does not fully exist in code yet) and Code Examples §2 |
| RENDER-03 | Offscreen framebuffer (color+depth), depth testing, no swapchain | See Architecture Patterns §Render Pass/Framebuffer, Pitfall 2 (DONT_CARE), Pitfall 7 (format support queries) |
| RENDER-04 | Pipeline state (topology/cull/winding) configurable via schema | See Architecture Patterns §Pipeline Creation — bake into `VkGraphicsPipelineCreateInfo`, do not use dynamic-state extensions |
| RENDER-05 | Push constants with descriptor-set UBO fallback at 128 bytes | See Code Examples §3, Pitfall 3 (std430 padding), Pitfall 8 (uniform "source" prefix ambiguity) |
| RENDER-06 | `vkCmdCopyImageToBuffer` readback exposed as `texture2D` via `pass_io_binding` output | See Architecture Patterns §Readback, Pitfall 4 (layout transitions), Pitfall 1 (output resolution gap) |
| RENDER-07 | Optional `data_transform` post-processing | See Pitfall 9 — **no `data_transform` executor exists anywhere in the codebase today**; this is a schema-only, currently-dead field |
| RENDER-08 | Output feeds unmodified `ProcessingResult` → `FileManager::SaveASync` → hash path | See Architecture Patterns §Integration Points — confirmed unmodified in `ProcessingManager::Process()` |
| RENDER-09 | `VkResult` failures map to structured `ProcessingManager::Error`-style values | See Don't Hand-Roll / Error Surfacing pattern below; note this is a NEW type distinct from the existing `ProcessingManager::Error` (outcome-based, manager-level) |
| DETV-01 | Bit-exact hash match, N≥10 repeat runs, same node | See Common Pitfalls (determinism cluster), Architecture Patterns §Determinism Guards |
| DETV-02 | Architectural guards: explicit clears, `VK_SAMPLE_COUNT_1_BIT`, fixed precision, no unordered reduction | See Architecture Patterns §Determinism Guards, Code Examples §4 |

</phase_requirements>

## Summary

Phase 3 fills in `RenderProcessor::StartProcessing()`, which today only calls the already-working `InitializeContext()` (headless `VkInstance`/`VkDevice`/`VkQueue` via vk-bootstrap, Phase 1) and returns a zero hash. Everything from pipeline construction through readback is greenfield Vulkan code inside this one file (plus a small, explicitly-scoped edit to `ProcessingManager::Process()`'s dispatch gate for RENDER-09/D-27/D-28). No new external dependencies are introduced — `Vulkan::Vulkan` and `vk-bootstrap::vk-bootstrap` are already linked into the `SGProcessors` target from Phase 1.

The Vulkan API mechanics themselves (offscreen render pass, graphics pipeline from SPIR-V, vertex/index buffers, push constants vs. UBO, command buffer recording, `vkCmdCopyImageToBuffer` readback) are well-established, stable-since-2016 API surface with abundant official documentation — this is the low-risk part of the phase. **The higher-risk finding from this research is that this codebase's actual data-plumbing does not yet support what RENDER-02/05/06 need**: `ProcessingManager::GetCidForProc()`/`Process()` currently fetches exactly two buffers for a render job (the packed, validated SPIR-V stages, and ONE arbitrary input blob resolved via a single "model index"), and there is no code anywhere that resolves a `pass_io_binding`-style `source:`/`target:` prefix reference against multiple independently-named inputs, outputs, or parameters. The only currently-working prefix resolution is the single `"input:" + name → index` map used once per job. The Phase 1 test fixture's `vertex_buffer.source == "input:renderInput"` happens to equal the same string used for the job's model-index lookup — this is coincidence, not a working general resolver. RENDER-02 (vertex AND index buffer, potentially different sources), RENDER-05 (uniform `source:` refs), and RENDER-06 (`target:`-addressed texture2D output) all need either new resolution code in `RenderProcessor` itself or an extension to `ProcessingManager`'s plumbing — this must be decided explicitly during planning, not discovered mid-implementation.

A second concrete gap: the Phase 2 SPIR-V wire format (`SerializeCompiledStages` in `ProcessingManager.cpp`) packs `stage_tag` + `word_count` + `words` per stage but drops each stage's `entry_point` string entirely. `VkPipelineShaderStageCreateInfo::pName` needs that string at pipeline-creation time. For GLSL-compiled stages this is almost always safe to hard-code as `"main"` (shaderc's conventional default), but for directly-submitted `spirv` stages the schema explicitly allows an arbitrary `entry_point`, and that information is lost by the time `RenderProcessor` sees the buffer. This is a real, previously-undiscovered gap between Phase 2's provisional wire format and Phase 3's actual consumption needs.

A third gap: `RENDER-07`'s "existing `data_transform` post-processing step" does not exist as executable code anywhere in the codebase — `DataTransform`/`DataTransformType` are schema-generated types with zero C++ consumers. The phrase "existing... step" in the roadmap/success-criteria is aspirational, not accurate to current code state.

**Primary recommendation:** Build `RenderProcessor`'s Vulkan mechanics using the well-established fixed-function-pipeline-per-job pattern (bake all pipeline state into `VkGraphicsPipelineCreateInfo`, no dynamic-state extensions — matches D-22's fresh-build-per-job policy exactly and avoids any Vulkan-1.3/extension version dependency). Before writing pipeline code, resolve — as an explicit planning decision, not left implicit — how `vertex_buffer`/`index_buffer`/uniform `source:` refs and the `texture2D` output `target:` ref actually get their bytes into/out of `RenderProcessor::StartProcessing()`, given the real (not aspirational) state of `ProcessingManager`'s data-fetch plumbing.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Schema-declared render pass definition (JSON) | Schema/Data (quicktype-generated) | — | Already complete (Phase 2); Phase 3 only consumes it |
| Buffer/parameter resolution (`pass_io_binding` source/target refs) | Backend/Dispatch (`ProcessingManager`) | Processor (`RenderProcessor`) | Currently under-built (see Summary) — must be decided this phase: extend `ProcessingManager`'s fetch plumbing vs. resolve locally inside `RenderProcessor` |
| Pipeline construction, buffer upload, draw, readback | GPU Execution (`RenderProcessor`, hand-rolled Vulkan) | — | The literal surface of this phase; owns all `Vk*` object lifetime per D-22/D-23/D-24 |
| Error classification (`VkResult` → structured message) | GPU Execution (`RenderProcessor`) | Backend/Dispatch (`ProcessingManager::Process()`'s D-27/D-28 gate) | Processor produces the error; dispatcher enforces "never save-and-hash a failed result" |
| Post-processing (`data_transform`) | Backend/Dispatch or Processor (undecided — no owner exists yet) | — | Genuinely unowned today; RENDER-07 either builds a minimal owner here or explicitly no-ops |
| Output persistence/hash (`FileManager::SaveASync`, hash) | Storage/Persistence (`ProcessingManager::Process()`) | — | Confirmed unmodified in code — RENDER-08 is satisfied by NOT touching this path |
| Vulkan instance/device lifetime | GPU Execution (`RenderProcessor::InitializeContext()`, Phase 1) | — | Already built; Phase 3 only adds per-job objects on top |

## Standard Stack

### Core

No new external libraries are introduced in this phase. Everything needed is already vendored and linked from Phase 1/2:

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Vulkan (loader + headers) | Already vendored (`thirdparty/Vulkan-Headers`, `thirdparty/Vulkan-Loader`) [VERIFIED: SuperGenius/SGProcessingManager/src/processors/CMakeLists.txt links `Vulkan::Vulkan`] | Raw Vulkan API calls for pipeline/buffers/command buffers/readback | Only viable hardware-Vulkan API per issue #7's "no new GPU backend" constraint |
| vk-bootstrap | v1.4.357, already pinned (Phase 1 D-01) [VERIFIED: `SGProcessors` CMakeLists links `vk-bootstrap::vk-bootstrap`] | Already used by `InitializeContext()` for instance/device/queue bootstrap only | Not used for per-job pipeline/buffer work — that's raw Vulkan (D-18) |

No memory allocator library (VMA explicitly rejected, D-18). No new shader toolchain (SPIR-V arrives pre-compiled/pre-validated from Phase 2's `ShaderCompiler`, consumed as raw bytes).

### Supporting

None — this phase adds zero new third-party dependencies.

### Alternatives Considered

Already resolved by locked decisions (D-18 through D-30); no alternatives to re-litigate per CONTEXT.md's explicit instruction.

**Installation:** None required — no `npm install`/`vcpkg install`/`ExternalProject_Add` changes needed for this phase. `RenderProcessor`'s `.cpp`/`.hpp` files already exist and are already in `SGProcessors`'s CMakeLists source list (`processing_processor_render.cpp` is already present).

**Version verification:** N/A — no new package versions to verify. Existing pins (`vk-bootstrap` v1.4.357) were already verified during Phase 1 planning.

## Package Legitimacy Audit

**Not applicable this phase.** Phase 3 installs zero new external packages/dependencies — it is pure C++ implementation against already-vendored, already-linked libraries (`Vulkan::Vulkan`, `vk-bootstrap::vk-bootstrap`) from Phase 1, and consumes Phase 2's `ShaderCompiler` output as opaque byte buffers. No `npm view`/`pip index`/`cargo search` verification is needed, and no `package-legitimacy check` run was performed since there is nothing to check.

**Packages removed due to [SLOP] verdict:** none (N/A — no packages evaluated)
**Packages flagged as suspicious [SUS]:** none (N/A — no packages evaluated)

## Architecture Patterns

### System Architecture Diagram

```
Job JSON (render pass definition)
        │
        ▼
ProcessingManager::Init()/CheckProcessValidity()   [Phase 2, done]
        │  (validates render_shader/render_target/vertex_buffer/vertex_layout present)
        ▼
ProcessingManager::GetCidForProc()                  [Phase 2, done]
        │  fetches per-stage GLSL/SPIR-V → ShaderCompiler::CompileAndValidate()
        │  (spirv-val gate — already mandatory, already enforced)
        │  packs validated SPIR-V → SerializeCompiledStages() wire format
        │  ⚠ fetches exactly ONE additional named input blob today (imageData)
        ▼
ProcessingManager::Process()
        │  dispatches PassType::RENDER → SetProcessorByPassType()
        │  → constructs a FRESH RenderProcessor (factory, every call)
        ▼
RenderProcessor::StartProcessing()                  [THIS PHASE — the gap]
        │
        ├─▶ InitializeContext()                     [Phase 1, done — VkInstance/Device/Queue]
        │
        ├─▶ Parse packed SPIR-V wire format → per-stage words + VkShaderStageFlagBits
        │       ⚠ entry_point strings NOT in wire format (Pitfall 6)
        │
        ├─▶ Resolve vertex_buffer / index_buffer / uniform sources
        │       ⚠ generic pass_io_binding source:/target: resolver DOES NOT EXIST
        │         beyond the single "input:name" → index map (Pitfall 1)
        │
        ├─▶ Build VkRenderPass + offscreen VkFramebuffer (color+depth)
        │       — explicit CLEAR load ops, VK_SAMPLE_COUNT_1_BIT (DETV-02)
        │
        ├─▶ Build VkGraphicsPipeline (vertex+fragment stages, baked
        │       topology/cull/front-face/depth-test from schema, D-14 fixed LESS)
        │
        ├─▶ Allocate + upload vertex/index/uniform buffers
        │       — dedicated VkDeviceMemory per buffer (D-19), HOST_VISIBLE|
        │         HOST_COHERENT direct write (D-20/D-21)
        │
        ├─▶ Record + submit ONE command buffer:
        │       BeginRenderPass → BindPipeline → BindVertex/IndexBuffers →
        │       PushConstants or BindDescriptorSets (D-29/D-30 threshold) →
        │       Draw(Indexed) → EndRenderPass → layout transition →
        │       CmdCopyImageToBuffer → fence submit → vkDeviceWaitIdle (D-23)
        │
        ├─▶ [optional] data_transform post-processing
        │       ⚠ NO EXECUTOR EXISTS ANYWHERE IN CODEBASE (Pitfall 9)
        │
        ├─▶ Destroy ALL per-job Vulkan objects (D-22/D-24, incl. on error paths)
        │
        └─▶ Populate ProcessingResult{ hash, output_buffers, NEW error field }
                │
                ▼
ProcessingManager::Process()  (D-27/D-28: check error field, skip save-on-failure)
        │
        ▼
FileManager::SaveASync()  →  output_locations / hash   [unmodified, RENDER-08]
```

### Recommended Project Structure

No new files are structurally required — everything lives in the existing pair:

```
SuperGenius/SGProcessingManager/
├── include/processors/processing_processor_render.hpp   # gains new private helpers/state
├── src/processors/processing_processor_render.cpp        # StartProcessing() fully implemented here
├── include/processors/processing_processor.hpp           # ProcessingResult gains new error field (D-25)
└── src/processingbase/ProcessingManager.cpp               # Process()'s D-27/D-28 error-check gate;
                                                            # possibly extended GetCidForProc() if the
                                                            # vertex/index/uniform resolution gap (Pitfall 1)
                                                            # is fixed at the manager level rather than
                                                            # inside RenderProcessor
```

Consider splitting `RenderProcessor`'s internals into private helper methods (e.g. `BuildRenderPass()`, `BuildPipeline()`, `UploadBuffers()`, `RecordAndSubmit()`, `Readback()`, `TeardownAll()`) within the same `.cpp` — this is a within-file organization choice, not a new-file decision, and keeps D-24's "destroy everything already created on any failure" tractable via a single ordered teardown list built up as each stage succeeds.

### Pattern 1: Fixed (non-dynamic) pipeline state, rebuilt per job

**What:** Bake `topology`/`cullMode`/`frontFace`/`depthTestEnable` directly into `VkGraphicsPipelineCreateInfo`'s `VkPipelineInputAssemblyStateCreateInfo`/`VkPipelineRasterizationStateCreateInfo`/`VkPipelineDepthStencilStateCreateInfo` at pipeline-creation time, rather than using `VK_DYNAMIC_STATE_CULL_MODE`/`FRONT_FACE`/`PRIMITIVE_TOPOLOGY`/`DEPTH_TEST_ENABLE` + the corresponding `vkCmdSet*` calls.

**When to use:** Always, for this phase. D-22 already mandates a fresh pipeline per job — there is no pipeline-reuse benefit to be gained from dynamic state, and dynamic cull/front-face/topology/depth-test-enable require either the `VK_EXT_extended_dynamic_state` extension or Vulkan 1.3 core [CITED: docs.vulkan.org/refpages VkDynamicState], neither of which is guaranteed available on every headless device this node might run on (Phase 1's device selection targets broad discrete/integrated GPU compatibility, not a specific Vulkan version floor).

**Example:**
```cpp
// Source: pattern synthesized from Vulkan spec (VkGraphicsPipelineCreateInfo,
// VkPipelineInputAssemblyStateCreateInfo, VkPipelineRasterizationStateCreateInfo,
// VkPipelineDepthStencilStateCreateInfo) — docs.vulkan.org/refpages/latest
VkPipelineInputAssemblyStateCreateInfo inputAssembly{};
inputAssembly.sType = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO;
inputAssembly.topology = ToVkTopology( pipelineState.get_topology() );  // schema enum -> Vk enum
inputAssembly.primitiveRestartEnable = VK_FALSE;

VkPipelineRasterizationStateCreateInfo rasterizer{};
rasterizer.sType = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO;
rasterizer.polygonMode = VK_POLYGON_MODE_FILL;
rasterizer.cullMode = ToVkCullMode( pipelineState.get_cull_mode() );
rasterizer.frontFace = ToVkFrontFace( pipelineState.get_front_face() );
rasterizer.lineWidth = 1.0f;

VkPipelineDepthStencilStateCreateInfo depthStencil{};
depthStencil.sType = VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO;
depthStencil.depthTestEnable = ToVkBool( pipelineState.get_depth_test() );
depthStencil.depthWriteEnable = depthStencil.depthTestEnable;  // ASSUMED: tie write to test (no
                                                                 // separate schema field exists)
depthStencil.depthCompareOp = VK_COMPARE_OP_LESS;  // fixed per D-14, never schema-configurable

VkPipelineMultisampleStateCreateInfo multisample{};
multisample.sType = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO;
multisample.rasterizationSamples = VK_SAMPLE_COUNT_1_BIT;  // ALWAYS — DETV-02, never configurable
```

### Pattern 2: Offscreen render pass with explicit clears, never DONT_CARE, on hashed regions

**What:** `VkAttachmentDescription` for both color and depth attachments uses `loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR` (never `DONT_CARE`) and `storeOp = VK_ATTACHMENT_STORE_OP_STORE` for the color attachment (the one that gets read back). `VK_ATTACHMENT_LOAD_OP_DONT_CARE` leaves contents undefined [CITED: docs.vulkan.org/samples/latest/samples/performance/render_passes] — a direct, silent threat to DETV-01's bit-exact hash claim if ever used on the color/depth attachments that participate in the final hashed output.

**Nuance for the depth attachment's stencil aspect:** if `depth_format` is `D24_UNORM_S8_UINT` (has a stencil component the schema never exposes/uses), `stencilLoadOp`/`stencilStoreOp` MAY legitimately be `DONT_CARE` — DETV-02's "never DONT_CARE" constraint applies to the attachments that actually feed the hashed readback (color, and depth only insofar as depth-testing affects which fragments write color), not to an unused stencil aspect that never reaches the host. Don't over-apply the guard to a component that was never going to be read back.

**Example:**
```cpp
// Source: pattern synthesized from Vulkan spec + Vulkan Tutorial render-passes chapter
// (vulkan-tutorial.com/Drawing_a_triangle/Graphics_pipeline_basics/Render_passes)
VkAttachmentDescription colorAttachment{};
colorAttachment.format = ToVkFormat( renderTarget.get_color_format() );
colorAttachment.samples = VK_SAMPLE_COUNT_1_BIT;              // DETV-02
colorAttachment.loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR;          // DETV-01/02 — never DONT_CARE
colorAttachment.storeOp = VK_ATTACHMENT_STORE_OP_STORE;        // must persist for readback
colorAttachment.stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE;
colorAttachment.stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
colorAttachment.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
colorAttachment.finalLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;  // ready for vkCmdCopyImageToBuffer
                                                                       // directly at render-pass end

VkAttachmentDescription depthAttachment{};
depthAttachment.format = ToVkFormat( renderTarget.get_depth_format() );
depthAttachment.samples = VK_SAMPLE_COUNT_1_BIT;
depthAttachment.loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR;          // DETV-01/02 — depth also cleared
depthAttachment.storeOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;    // depth not read back (schema has no
                                                                 // depth-output binding) — legitimate
                                                                 // DONT_CARE since not hashed
depthAttachment.stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE;
depthAttachment.stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
depthAttachment.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
depthAttachment.finalLayout = VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;
```

### Pattern 3: Single-submit, fence-gated command buffer for a headless batch job

**What:** One primary command buffer, recorded once (`VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT`), submitted once with a `VkFence`, waited on synchronously (`vkWaitForFences` or `vkDeviceWaitIdle` per D-23), then torn down. This is the textbook "single time commands" pattern [CITED: docs.vulkan.org/spec/latest/chapters/cmdbuffers, vkQueueSubmit reference] adapted for a discrete batch job rather than a frame loop — there is no frames-in-flight concern here since D-22 forbids any object reuse across jobs anyway.

**When to use:** Always, for this phase — this is not a real-time render loop (explicitly out of scope per REQUIREMENTS.md).

### Anti-Patterns to Avoid

- **Reusing MNN's `VulkanInitMutex` for anything beyond instance/device *creation*:** the mutex (Phase 1) guards `createSession()`/instance-creation call sites only. Per-job pipeline/buffer/draw work on RenderProcessor's own independent device does not need this lock — taking it unnecessarily around the whole `StartProcessing()` body would serialize render jobs against MNN inference jobs for no reason and contradicts D-23's coexistence resolution (independent devices don't need cross-device locking for normal operation).
- **Using `VK_DYNAMIC_STATE_*` for pipeline state to "save a rebuild":** unnecessary given D-22, and adds an extension/version dependency (Pattern 1).
- **Assuming `vertex_buffer.source == "input:renderInput"` generalizes:** the only fixture that exists today happens to reuse the model-index string; do not build `RenderProcessor` assuming this coincidence always holds for real job definitions with genuinely separate vertex/index/uniform sources (Pitfall 1).
- **Treating RGB8/D24_UNORM_S8_UINT as guaranteed-renderable formats:** they are common but not part of Vulkan's mandatory minimum format-feature guarantees for color-attachment/depth-stencil-attachment usage — query `vkGetPhysicalDeviceFormatProperties` before creating images/render pass and fail cleanly (RENDER-09) rather than let pipeline/framebuffer creation fail with an opaque `VkResult` or hit driver-undefined behavior (Pitfall 7).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Vulkan instance/device/queue bootstrap | A second bootstrap path | `RenderProcessor::InitializeContext()` (Phase 1, already done) | Already implemented, already uses vk-bootstrap + deterministic device scoring |
| GLSL→SPIR-V compilation / `spirv-val` validation | Any shader compile/validate call inside `RenderProcessor` | `sgns::sgprocessing::ShaderCompiler` (Phase 2, already done, runs entirely at `GetCidForProc()` time) | `RenderProcessor` receives already-compiled, already-validated SPIR-V words — it must never call shaderc/SPIRV-Tools itself |
| GPU memory sub-allocation / pooling | A custom block allocator or bump allocator | Direct `vkAllocateMemory` per buffer/image (D-18/D-19) | Explicitly, deliberately rejected in favor of simplicity for this job's small allocation count (~5-8 sites) — do not "improve" this during implementation |
| Manual memory flush/invalidate bookkeeping | `vkFlushMappedMemoryRanges`/`vkInvalidateMappedMemoryRanges` call sites | `HOST_VISIBLE \| HOST_COHERENT` memory everywhere host-visible memory is used (D-20) | A missed/misaligned manual flush is a direct, silent, hard-to-debug threat to DETV-01 |
| Cross-job Vulkan object caching | A pipeline/framebuffer/buffer cache keyed by job hash | Full rebuild + full teardown every call (D-22) | Zero shared mutable GPU state is the entire simplicity argument for DETV-01's determinism story — do not add a cache "for performance" without renegotiating this decision |

**Key insight:** Nearly every "don't hand-roll" item in this phase is a *decision already made* (D-18 through D-24), not a discovery this research needed to make. The one genuinely open "don't hand-roll (yet)" question is `data_transform` post-processing (RENDER-07) — there is no existing executor to reuse, and building a general one is out of proportion to this phase; a minimal, explicitly-scoped implementation (or an explicit no-op-if-absent, error-if-present stance) should be a planning decision, not an implementation-time surprise.

## Common Pitfalls

### Pitfall 1: The "existing pass_io_binding resolution mechanism" does not fully exist yet
**What goes wrong:** Planning proceeds assuming `RenderProcessor` can simply "resolve" `vertex_buffer.get_source()`, `index_buffer.get_source()`, and each uniform's `source` field the same way `pass_io_binding`'s `input:`/`output:`/`internal:`/`parameter:` convention is resolved elsewhere — but grep across `SuperGenius/SGProcessingManager/src` confirms the ONLY working resolution code is `ProcessingManager::Init()`'s `"input:" + inputs[i].get_name() → index` map (`m_inputMap`), consumed via `GetInputIndex()` for exactly one lookup per job (the model-index lookup in `Process()`/`GetCidForProc()`). There is no C++ code anywhere that resolves `output:`/`internal:`/`parameter:` prefixes, and no code that fetches more than one additional named input per job.
**Why it happens:** The schema convention (regex-constrained prefix strings) was locked in Phase 2, but the *C++ resolver* for anything beyond the single "input:" case was never built — Phase 1/2's test fixtures only ever exercise a single input (`renderInput`) whose name happens to match both the model-index lookup and the `vertex_buffer.source` reference.
**How to avoid:** Decide explicitly during planning whether Phase 3 (a) extends `ProcessingManager::GetCidForProc()`/`Process()` to fetch each of vertex-buffer/index-buffer/uniform-`source:` inputs independently and pass them to `RenderProcessor` (likely requiring a `StartProcessing()`-adjacent data-shape change, though D-25 restricts changing the *signature* — extra buffers could ride inside `imageData`/a new packed format similar to `SerializeCompiledStages`), or (b) has `RenderProcessor` itself walk `processing_.get_inputs()`/`get_outputs()` — but `RenderProcessor` does not currently have access to the full `SgnsProcessing`/`Pass` object, only the single resolved `IoDeclaration &proc` — meaning option (b) likely also requires a data or method surface change upstream of `RenderProcessor`.
**Warning signs:** A plan that says "resolve `vertex_buffer.source` via the existing mechanism" without pointing at actual reusable code is describing aspiration, not fact — cross-check any such claim against `ProcessingManager.cpp`/`.hpp` before accepting it into a plan.

### Pitfall 2: `VK_ATTACHMENT_LOAD_OP_DONT_CARE` anywhere on hashed regions silently breaks DETV-01
**What goes wrong:** `DONT_CARE` load ops leave attachment contents undefined at render-pass start; a driver may legitimately return different garbage bytes run-to-run (different memory reuse patterns), producing a different hash every time even though the actual draw logic is fully deterministic.
**Why it happens:** `DONT_CARE` is a common "just get it compiling" default copy-pasted from tutorials that assume swapchain-style full-frame overwrite; this job's `render_target` D-15 requires explicit `clear_color`/`clear_depth` values precisely so `CLEAR` (not `DONT_CARE`) can always be used.
**How to avoid:** Always use `VK_ATTACHMENT_LOAD_OP_CLEAR` with the schema-provided `clear_color`/`clear_depth` for color+depth. `DONT_CARE` is only acceptable for the unused stencil aspect (see Pattern 2).
**Warning signs:** Any code review or test that runs the determinism check (N≥10 same-node repeats) and sees a hash mismatch should check attachment load ops first.

### Pitfall 3: std430 push-constant/UBO padding silently produces wrong (but "deterministic") values
**What goes wrong:** SPIR-V push-constant blocks are laid out per std430 rules [CITED: docs.vulkan.org/guide/latest/push_constants], where a `vec3` still has a 16-byte base alignment despite being 12 bytes wide. If the host-side C++ struct used to `memcpy` into the push-constant range doesn't match this padding exactly, the shader reads shifted/wrong values — often *consistently* wrong (same wrong value every run), which can pass a naive N≥10 same-node repeat-hash determinism check while still being functionally incorrect.
**Why it happens:** C++ struct layout rules (natural alignment) don't automatically match GLSL/SPIR-V std430 rules; `vec3 position; float scale;` in GLSL does NOT tightly pack in memory the way the equivalent C++ struct might.
**How to avoid:** Either restrict push-constant/UBO uniform declarations to `vec4`/`mat4`-aligned types only (simplest, avoids the trap entirely), or hand-compute std430 offsets/padding explicitly per uniform and document them at the packing site.
**Warning signs:** A uniform value visibly "off" (e.g. an MVP matrix producing a shifted/skewed image) despite the pipeline otherwise working.

### Pitfall 4: Missing/incorrect image layout transition before `vkCmdCopyImageToBuffer`
**What goes wrong:** `vkCmdCopyImageToBuffer` requires the source image to be in `VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL` (or general layout) at the time of the copy. If the render pass's `finalLayout` for the color attachment is left at `COLOR_ATTACHMENT_OPTIMAL`, the copy needs an explicit `vkCmdPipelineBarrier` layout transition first — omitting it is a validation-layer error in debug builds and undefined-behavior-adjacent on release/no-validation builds (silently wrong or garbage readback).
**Why it happens:** Tutorials often stop at `vkCmdEndRenderPass` (for swapchain present) and don't cover the offscreen-readback case, since the swapchain path never needs this specific transition.
**How to avoid:** Either set the color attachment's `finalLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL` directly (Pattern 2's example does this, avoiding a separate barrier entirely) or add the explicit barrier between `vkCmdEndRenderPass` and `vkCmdCopyImageToBuffer`.
**Warning signs:** Validation layers report a layout mismatch (if CTX-04's deferred ValidationLayers work ever lands, this becomes directly visible); without validation layers, readback silently returns wrong/garbage data.

### Pitfall 5: `RenderProcessor` instance/device recreation cost is paid on every subtask, not amortized across jobs
**What goes wrong:** `ProcessingManager::Create()` is invoked fresh for every `ProcessSubTask()` call in `processing_core_impl.cpp` (confirmed via grep — no caching by task/manager identity), and `SetProcessorByPassType()` always constructs a brand-new `RenderProcessor` via its factory lambda. This means `InitializeContext()`'s full `vkb::InstanceBuilder`/`PhysicalDeviceSelector`/`DeviceBuilder` cost is paid on literally every render subtask, not just "on first render-job arrival on this node" as Phase 1's D-06 wording might suggest.
**Why it happens:** D-06's "lazy init" framing describes WHEN the first-ever Vulkan init happens relative to node startup (good — avoids idle GPU resources on nodes that never render), but the current job-dispatch object-lifecycle (fresh `ProcessingManager`/`RenderProcessor` per subtask) means there is no actual multi-job persistence happening in practice today.
**How to avoid:** This is NOT a defect to fix in Phase 3 — D-22/D-23 already assume/require full per-job teardown anyway, so this reality is consistent with (not contradictory to) this phase's locked decisions. Flagging it here only so the planner doesn't assume any instance-reuse optimization is available, and doesn't mistake "no reuse happens" for a bug introduced by this phase's own code.
**Warning signs:** None to fix — this is background context, not an action item, unless a future phase revisits node-level performance.

### Pitfall 6: The Phase 2 SPIR-V wire format drops each stage's `entry_point` string
**What goes wrong:** `SerializeCompiledStages()` (`ProcessingManager.cpp`) packs `stage_count`, then per stage `{stage_tag(u32), word_count(u32), words[]}` — no `entry_point` string anywhere in the format. `VkPipelineShaderStageCreateInfo::pName` needs that entry-point name at pipeline-creation time.
**Why it happens:** The wire format was built during Phase 2 as an explicitly "provisional... this plan's own choice, not a negotiated Phase-3 contract" placeholder (see the comment directly above `SerializeCompiledStages` in `ProcessingManager.cpp`) before `RenderProcessor`'s actual consumption needs were known.
**How to avoid:** Two options to weigh during planning: (a) hard-code `pName = "main"` for every stage (safe for GLSL-compiled stages if `ShaderCompiler` always targets `"main"` regardless of the job's declared `entry_point`, but silently wrong for directly-submitted `spirv` stages whose original entry-point name the schema explicitly allows to differ), or (b) extend the wire format to carry each stage's entry-point string (a small, backward-compatible-if-done-carefully addition, but touches Phase 2 code in Phase 3). This is a real decision the planner must make, not an implementation detail to improvise.
**Warning signs:** A directly-submitted (`shader_config.type: "spirv"`/`shader_stage.type: "spirv"`) shader stage with a non-`"main"` entry point fails pipeline creation with `VK_ERROR_INVALID_SHADER_NV` or produces a "shader stage has no entry point" validation error.

### Pitfall 7: Schema-selectable color/depth formats are not guaranteed renderable on every device
**What goes wrong:** `ColorFormat` (`RGB8`/`RGBA8`) and `DepthFormat` (`D24_UNORM_S8_UINT`/`D32_SFLOAT`) are schema enums a job author picks freely (D-15: all `render_target` fields required, no defaults). Vulkan's mandatory minimum format-feature guarantees do not cover 3-component 8-bit formats (`RGB8`) as color-attachment-capable on all implementations, and `D24_UNORM_S8_UINT` specifically is not part of the guaranteed depth-stencil-attachment pairing (the guaranteed alternative is `D32_SFLOAT_S8_UINT`, a format this schema doesn't even expose) [ASSUMED — training-knowledge recollection of Vulkan's format-support guarantee table; not verified against the current spec text this session].
**Why it happens:** The schema was designed (Phase 2) around ergonomic format names without cross-checking Vulkan's actual per-format feature-support guarantees.
**How to avoid:** Before creating the render-pass/images, call `vkGetPhysicalDeviceFormatProperties`/`FormatProperties2` for the requested `color_format`/`depth_format` and check `VK_FORMAT_FEATURE_COLOR_ATTACHMENT_BIT`/`VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT` are present; if not, fail with a clear RENDER-09 structured error rather than let image/render-pass creation return an opaque `VkResult` or (without validation layers) silently misbehave.
**Warning signs:** `vkCreateImage`/`vkCreateRenderPass` returning `VK_ERROR_FORMAT_NOT_SUPPORTED` (or, worse, succeeding but producing wrong output) on some GPU vendors and not others.

### Pitfall 8: `RenderShaderUniform.source`'s prefix convention is not schema-enforced the way `vertex_buffer`/`index_buffer` are
**What goes wrong:** `vertex_buffer.source` and `index_buffer.source` carry the regex `^(input|output|internal|parameter):[a-zA-Z][a-zA-Z0-9_]*$` in the schema (`gnus-processing-schema.json`), but `render_shader_config.uniforms[].source` and `shader_config.uniforms[].source` are declared as a bare `"type": "string"` with NO pattern constraint. A job author's uniform `source` string is not schema-guaranteed to follow the `input:`/`parameter:` convention at all.
**Why it happens:** Likely an oversight during Phase 2's schema authoring — Phase 2's `<decisions>` D-11/D-12 discuss uniforms' shared-map shape but never explicitly lock uniform `source`'s exact string format the way D-16/D-16-Amendment lock `vertex_buffer`.
**How to avoid:** Treat uniform `source` resolution as needing its own explicit validation/parsing in `RenderProcessor` (or `CheckProcessValidity()`) — don't assume the regex that governs `vertex_buffer`/`index_buffer` also governs uniforms; check for the `parameter:`/`input:` prefix defensively and reject malformed values with a clear RENDER-09 error rather than a crash.
**Warning signs:** A job with an unprefixed or malformed uniform `source` string reaching `RenderProcessor` unchecked.

### Pitfall 9: `data_transform` (RENDER-07) has zero existing executor code
**What goes wrong:** Planning treats "flows through the existing `data_transform` post-processing step" as reuse of working code. Grep across `SuperGenius/SGProcessingManager/src` for `get_data_transforms`/`DataTransformType`/any transform-application logic returns zero matches — `DataTransform`/`DataTransformType` are quicktype-generated schema types with no C++ consumer anywhere.
**Why it happens:** The schema field was defined generically (Phase 2 predecessor work, not this workstream) for future extensibility across all pass types, but no pass type has ever actually implemented it.
**How to avoid:** Scope RENDER-07 explicitly during planning: either (a) implement a minimal executor for a small subset of `DataTransformType` values actually needed by real render-pass use cases (likely none needed for a first working vertical slice), or (b) implement RENDER-07 as "no-op if `data_transforms` absent/empty; return a clear RENDER-09-style unimplemented-transform error if present" — satisfying the literal requirement ("output CAN optionally flow through... " — optional, not mandatory) without building unused general infrastructure.
**Warning signs:** A plan task that says "apply the existing data_transform pipeline" without first confirming there is one to apply.

## Code Examples

### 1. Parsing the packed SPIR-V wire format (mirrors `SerializeCompiledStages`)
```cpp
// Source: derived directly from ProcessingManager.cpp's SerializeCompiledStages()
// comment block (this codebase, not an external doc) — RenderProcessor must be the
// exact inverse of this function.
struct ParsedStage { sgns::Stage stage; std::vector<uint32_t> spirv; };

std::vector<ParsedStage> ParseCompiledStages( const std::vector<char> &modelFile )
{
    std::vector<ParsedStage> stages;
    size_t offset = 0;
    auto readU32 = [&]() {
        uint32_t v;
        std::memcpy( &v, modelFile.data() + offset, sizeof( uint32_t ) );
        offset += sizeof( uint32_t );
        return v;
    };
    uint32_t stageCount = readU32();
    for ( uint32_t i = 0; i < stageCount; ++i )
    {
        ParsedStage s;
        s.stage = static_cast<sgns::Stage>( readU32() );
        uint32_t wordCount = readU32();
        s.spirv.resize( wordCount );
        std::memcpy( s.spirv.data(), modelFile.data() + offset, wordCount * sizeof( uint32_t ) );
        offset += wordCount * sizeof( uint32_t );
        stages.push_back( std::move( s ) );
    }
    return stages;
}
```

### 2. `VkShaderModule` + `VkPipelineShaderStageCreateInfo` from parsed SPIR-V
```cpp
// Source: pattern synthesized from Vulkan spec (vkCreateShaderModule,
// VkPipelineShaderStageCreateInfo) — docs.vulkan.org/refpages/latest
VkShaderModuleCreateInfo moduleInfo{};
moduleInfo.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
moduleInfo.codeSize = stage.spirv.size() * sizeof( uint32_t );
moduleInfo.pCode = stage.spirv.data();
VkShaderModule module;
VkResult r = vkCreateShaderModule( device, &moduleInfo, nullptr, &module );
// map r != VK_SUCCESS -> structured per-stage RENDER-09 error (D-26), destroy nothing yet (D-24)

VkPipelineShaderStageCreateInfo stageInfo{};
stageInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
stageInfo.stage = ( stage.stage == sgns::Stage::VERTEX )
                     ? VK_SHADER_STAGE_VERTEX_BIT : VK_SHADER_STAGE_FRAGMENT_BIT;
stageInfo.module = module;
stageInfo.pName = "main";  // See Pitfall 6 re: entry_point loss in the wire format
```

### 3. Push-constant vs. descriptor-set UBO threshold (D-29/D-30)
```cpp
// Source: pattern synthesized from Vulkan spec (VkPushConstantRange,
// VkPhysicalDeviceLimits::maxPushConstantsSize) — docs.vulkan.org/refpages/latest
constexpr uint32_t kPushConstantThreshold = 128;  // spec-guaranteed floor, D-29 — never queried

uint32_t packedUniformBytes = ComputePackedUniformSize( renderShader.get_uniforms() );

if ( packedUniformBytes <= kPushConstantThreshold )
{
    VkPushConstantRange range{};
    range.stageFlags = VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT;
    range.offset = 0;
    range.size = packedUniformBytes;
    // pipelineLayoutInfo.pPushConstantRanges = &range; pipelineLayoutInfo.pushConstantRangeCount = 1;
}
else
{
    // D-30: ALL uniforms move together into ONE descriptor-set UBO — no partial spill.
    // Build a single VkDescriptorSetLayout (one UBO binding), one-set VkDescriptorPool
    // (maxSets = 1, matching D-22's per-job-only lifetime), one VkBuffer/VkDeviceMemory
    // (HOST_VISIBLE|HOST_COHERENT direct write per D-20/D-21), one VkWriteDescriptorSet.
}
```

### 4. Determinism-guard multisample/precision setup (DETV-02)
```glsl
// Source: pattern derived from DETV-02's requirement text + GLSL precision-qualifier
// semantics (Vulkan GLSL defaults to highp for float in fragment shaders when
// GL_ARB_shading_language_420pack / SPIR-V target is used, but explicit qualifiers
// remove ambiguity across compiler versions)
#version 450
precision highp float;   // explicit — never rely on an implicit/varying default
```
```cpp
// Host-side: VK_SAMPLE_COUNT_1_BIT always (never configurable, never queried from device
// max sample count) — see Pattern 1's VkPipelineMultisampleStateCreateInfo example.
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|---------------|--------|
| Baking cull/front-face/topology/depth-test into the pipeline (this phase's chosen approach) | `VK_EXT_extended_dynamic_state` / Vulkan 1.3 core dynamic state | Extension: ~2020; core: Vulkan 1.3 (2022) | Not adopted here — D-22's fresh-pipeline-per-job policy removes the motivation (reduced pipeline permutations) that dynamic state exists to solve, and avoids a version/extension dependency on every target device |

**Deprecated/outdated:** None directly relevant — this phase's Vulkan API surface (render passes, graphics pipelines, push constants, `vkCmdCopyImageToBuffer`) is stable core-1.0 API with no deprecation in flight. (Note: `VK_KHR_dynamic_rendering`, which lets you skip `VkRenderPass`/`VkFramebuffer` objects entirely, exists as a more modern alternative pattern, but was not evaluated here since D-22/D-23/D-24's fresh-build-every-job design doesn't need it and `VkRenderPass`/`VkFramebuffer` remain fully supported, non-deprecated core API.)

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `depthWriteEnable` should be tied to `depthTestEnable` (schema has no separate write-enable field) | Architecture Patterns §Pattern 1 | Low — if wrong, depth buffer wouldn't update on writes with test-enabled-only jobs; easy to catch via any depth-dependent rendering test, no security/determinism impact either way (still deterministic, just possibly not the intended depth behavior) |
| A2 | `RGB8`/`D24_UNORM_S8_UINT` are not universally guaranteed renderable formats (Pitfall 7) | Common Pitfalls §Pitfall 7 | Medium — if this recollection is wrong (i.e., these formats ARE effectively universal in practice on the target platform set), the format-support query becomes defensive-but-unnecessary code rather than load-bearing; if right and skipped, produces platform-dependent crashes/failures on some GPU vendors that DETV-01/E2E-02 (MoltenVK) would then surface late |
| A3 | Hard-coding `pName = "main"` for GLSL-compiled stages is safe because `ShaderCompiler`/shaderc's conventional default targets `"main"` regardless of source function renaming | Common Pitfalls §Pitfall 6, Code Examples §2 | Medium — if shaderc does NOT always normalize the compiled SPIR-V's entry point to literally `"main"` (e.g., preserves a non-`"main"` `entry_point` string from the job's `shader_stage.entry_point` field), pipeline creation fails for any job using a non-default entry point name; should be spot-checked against `ShaderCompiler::CompileAndValidate()`'s actual shaderc invocation during planning/implementation, not assumed |

**All three above stem from training-knowledge Vulkan-spec recollection or reasonable-but-unverified inference about existing Phase 2 code behavior — none are blocking, but A3 in particular should be confirmed by reading `shader_compiler.cpp`'s actual `shaderc::Compiler::CompileGlslToSpv` call before finalizing the pipeline-shader-stage code.**

## Open Questions

1. **Where does vertex/index/uniform buffer resolution actually live?**
   - What we know: The schema convention (`source:`/`target:` prefix notation) is fully locked (Phase 2). The only working C++ resolver today is the single "input:name → index" map used once per job for the model-index lookup.
   - What's unclear: Whether Phase 3's plan should extend `ProcessingManager`'s fetch plumbing (`GetCidForProc`/`Process`) to resolve multiple named buffers per render job, or have `RenderProcessor` reach into a broader data surface itself.
   - Recommendation: Resolve this as an explicit planning decision (likely its own plan/task) before any pipeline-construction code is written — it gates RENDER-02, RENDER-05, and RENDER-06 simultaneously.

2. **What exactly should RENDER-07's `data_transform` support in this phase?**
   - What we know: No executor exists at all today; the field is schema-only.
   - What's unclear: Whether "optionally flow through" implies Phase 3 must build a working (even if minimal) executor, or whether a no-op-when-absent/error-when-present stance satisfies the requirement's literal wording.
   - Recommendation: Treat as in-scope-but-minimal — a no-op passthrough is almost certainly sufficient for a first working vertical slice, given no fixture or requirement text describes a specific transform a render pass actually needs applied.

3. **Does the Phase 2 wire format need to gain `entry_point` strings, or is `"main"`-always safe?**
   - What we know: The wire format as built has no room for it; GLSL-compiled stages conventionally target `"main"`.
   - What's unclear: Whether directly-submitted (`spirv` type) stages with non-`"main"` entry points are a real near-term use case worth building for now vs. deferring.
   - Recommendation: Spot-check `shader_compiler.cpp`'s shaderc invocation to see whether entry-point renaming already happens; if the direct-`spirv` path is exercised by any real fixture/test, extending the wire format is probably cheaper than debugging a silent pipeline-creation failure later.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Vulkan loader/headers/driver (hardware) | RENDER-01..09, DETV-01/02 | ✓ (already vendored + linked, Phase 1) | Vulkan-Headers/Loader per `thirdparty/.gitmodules` (Phase 1-pinned) | None — hardware Vulkan is mandatory per issue #7, no CPU/software fallback permitted |
| vk-bootstrap | `InitializeContext()` (Phase 1, unchanged this phase) | ✓ | v1.4.357 [VERIFIED: Phase 1 D-01 lock, `SGProcessors` CMakeLists] | N/A |
| `ShaderCompiler`/shaderc/SPIRV-Tools | Upstream of this phase (already-compiled SPIR-V arrives as input) | ✓ (Phase 2, unchanged this phase) | Per Phase 2 STACK.md pins | N/A — `RenderProcessor` never calls these directly |
| Full MSBuild link-build of `SGProcessingManager`/`ProcessingBase` in this working tree | Verifying this phase's code actually compiles/links end-to-end (not just `cl.exe /Zs` syntax-check) | ⚠ Unverified per STATE.md's carried-forward Blocker | — | STATE.md explicitly recommends a real from-scratch (or restored ephemeral) build+test run early in Phase 3, before or alongside implementation — this is a build-environment risk, not a design risk |

**Missing dependencies with no fallback:** none identified for this phase's actual Vulkan/build dependencies.
**Missing dependencies with fallback:** none — the one real environment risk (unverified full build) has no code-level fallback, only a process recommendation (verify build early, per STATE.md's carried-forward concern).

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No | Not applicable — this is an internal compute-node processing path, no auth surface added |
| V3 Session Management | No | Not applicable |
| V4 Access Control | No | Not applicable — job definitions are already trusted-enough-to-execute by the time they reach `RenderProcessor` (SHADER-02's `spirv-val` gate is the relevant trust boundary, already enforced in Phase 2) |
| V5 Input Validation | Yes | Job-supplied `render_target` dimensions/formats, `vertex_layout` offsets, and uniform byte sizes must all be validated before being used to size Vulkan allocations — an untrusted job could specify a pathological `width`/`height` (schema only enforces `minimum: 1`, no maximum) or a `vertex_layout` offset/format combination whose implied stride mismatches the actual uploaded buffer's size. Standard control: bounds-check `render_target.width/height` against a sane node-configured maximum before calling `vkCreateImage` (an unbounded allocation request is a resource-exhaustion vector on a shared distributed-compute node), and validate that the resolved vertex-buffer's byte length is an exact multiple of the schema-declared (auto-computed, per D-16) stride before uploading — reject with a RENDER-09 structured error otherwise. |
| V6 Cryptography | No | Not applicable — no new cryptographic operations in this phase (existing SHA-256 hash path, RENDER-08, is explicitly unmodified) |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Malformed/oversized `render_target` dimensions causing excessive GPU memory allocation | Denial of Service | Bounds-check `width`/`height` against a sane maximum (node-configurable) before `vkCreateImage`; already-enforced `spirv-val` (Phase 2) covers the shader-bytecode side of this concern but not the render-target/buffer-sizing side |
| Vertex/index buffer byte-length mismatch vs. schema-declared layout/stride/index-count | Tampering / Information Disclosure (out-of-bounds GPU buffer read) | Validate resolved buffer byte length against the schema-declared vertex stride × implied vertex count (and index buffer length against index type × count) before `vkCmdBindVertexBuffers`/`vkCmdBindIndexBuffer`/`vkCmdDrawIndexed` — a driver may read out-of-bounds GPU memory if a job under-supplies buffer bytes relative to what the pipeline/draw call implies |
| Directly-submitted (`type: "spirv"`) shader bytecode reaching `vkCreateShaderModule` unvalidated | Tampering (malicious/malformed SPIR-V as a driver-crash vector) | Already fully mitigated — Phase 2's `ShaderCompiler::CompileAndValidate()` runs `spvtools::SpirvTools::Validate()` unconditionally on every code path (both GLSL-compiled and direct-SPIR-V) before `RenderProcessor` ever sees the bytes; RENDER-01 must not add any second path that could bypass this gate |

## Sources

### Primary (HIGH confidence)
- This codebase (direct file reads + `Grep`): `processing_processor_render.hpp/.cpp`, `processing_processor.hpp`, `processing_processor_mnn_image.cpp`, `ProcessingManager.cpp/.hpp`, `shader_compiler.hpp`, `vulkan_init_guard.hpp`, `gnus-processing-schema.json`, all `generated/*.hpp` render-related headers, `processing_dispatch_test.cpp` + its JSON/GLSL fixtures, `processing_core_impl.cpp`, `SGProcessors`'s `CMakeLists.txt` — all findings about "what actually exists today vs. what's aspirational" are grounded here, not inferred.
- `.planning/workstreams/sgproc-render/{REQUIREMENTS,STATE}.md` and Phase 1/2/3 `*-CONTEXT.md` files — locked decisions, canonical refs, carried-forward blockers.

### Secondary (MEDIUM confidence — web search cross-checked against Khronos/official domains)
- [Render passes - Vulkan Tutorial](https://vulkan-tutorial.com/Drawing_a_triangle/Graphics_pipeline_basics/Render_passes) — load/store op semantics
- [Appropriate use of render pass attachments — Vulkan Documentation Project](https://docs.vulkan.org/samples/latest/samples/performance/render_passes/README.html) — DONT_CARE vs CLEAR determinism framing
- [VkDynamicState — Vulkan Documentation Project](https://docs.vulkan.org/refpages/latest/refpages/source/VkDynamicState.html) — dynamic cull/front-face/topology/depth-test-enable extension/version gating
- [VkGraphicsPipelineCreateInfo — Vulkan Documentation Project](https://docs.vulkan.org/refpages/latest/refpages/source/VkGraphicsPipelineCreateInfo.html)
- [VkPhysicalDeviceLimits — Vulkan Documentation Project](https://docs.vulkan.org/refpages/latest/refpages/source/VkPhysicalDeviceLimits.html) — `maxPushConstantsSize` guaranteed-128-byte floor
- [Push Constants — Vulkan Documentation Project](https://docs.vulkan.org/guide/latest/push_constants.html) and [Push Constants — Vulkan Guide](https://vkguide.dev/docs/chapter-3/push_constants/) — std430 layout, vec3 padding trap
- [Command Buffers — Vulkan Documentation Project](https://docs.vulkan.org/spec/latest/chapters/cmdbuffers.html) and [vkQueueSubmit — Vulkan Documentation Project](https://docs.vulkan.org/refpages/latest/refpages/source/vkQueueSubmit.html) — fence-gated single-submit pattern

### Tertiary (LOW confidence — training-knowledge recollection, flagged in Assumptions Log)
- Vulkan mandatory-minimum format-feature-support guarantees for `RGB8`/`D24_UNORM_S8_UINT` specifically (Pitfall 7 / A2) — not re-verified against current spec text this session; treat as a reason to add a defensive format-support query, not as a certainty about which exact formats will fail on which exact devices.
- shaderc's entry-point-renaming behavior (A3) — should be confirmed against `shader_compiler.cpp`'s actual implementation before finalizing pipeline-shader-stage code.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new dependencies, existing pins already verified in prior phases
- Architecture (this-codebase data-flow gaps): HIGH — grounded in direct grep/read of the actual C++ source, not inference
- Architecture (Vulkan API mechanics): HIGH — stable, well-documented, cross-checked against Khronos's own documentation project
- Pitfalls: MEDIUM-HIGH — mix of codebase-grounded (HIGH: Pitfalls 1, 5, 6, 9) and Vulkan-spec-general (MEDIUM: Pitfalls 2, 3, 4, 7, 8)
- Determinism sufficiency (DETV-01/02): MEDIUM — the guards are the correct, standard ones for the known failure classes, but "bit-exact across N≥10 runs" is an empirical claim only the phase's own repeat-run test can actually prove; research can only confirm the guards target real, documented non-determinism sources

**Research date:** 2026-07-31
**Valid until:** 30 days (stable Vulkan core API; the this-codebase findings, e.g. Pitfall 1/6/9, will change the moment Phase 3 implementation lands, so re-check against current code state if this document is consulted after Phase 3 completes)
