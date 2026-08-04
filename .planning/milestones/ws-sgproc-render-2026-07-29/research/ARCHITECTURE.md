# Architecture Patterns

**Domain:** Distributed processing-job execution (SGProcessingManager) — integrating a headless Vulkan render pass alongside an existing MNN-inference-shaped dispatch system
**Researched:** 2026-07-28

## Recommended Architecture

### Current architecture (as-is, verified from source)

```
ProcessingCoreImpl::ProcessSubTask(SGProcessing::SubTask)
    │
    ├─ ProcessingManager::Create(task.json_data())         // parses whole SgnsProcessing doc, builds m_inputMap
    │      └─ CheckProcessValidity()                       // per-pass switch(PassType) — RENDER: break (no-op today)
    │
    ├─ ProcessingManager::GetModelNodeFromJson(subTask.json_data())
    │      → sgns::ModelNode  (one input_node/output_node entry — "input:<name>" or "output:<name>")
    │
    └─ processing_manager_->Process(ioc, chunk_hashes, model, output_locations)
           │
           ├─ GetInputIndex(model.get_source())              // "input:foo" → index i into processing_.get_inputs()
           ├─ GetCidForProc(ioc, model)                       // fetches BOTH:
           │        processing_.get_passes()[i].get_model().value().get_source_uri_param()   ← model file
           │        processing_.get_inputs()[i].get_source_uri_param()                        ← data file
           │        (NOTE: indexes passes[] by the *input* index i — an undocumented
           │         1:1 positional assumption between inputs[] and passes[], not a
           │         name-based lookup. This only works because today's schemas are
           │         single-pass/single-model.)
           ├─ SetProcessorByName(inputs[i].get_type())        // DataType → m_processorFactories → m_processor
           ├─ m_processor->StartProcessing(chunkhashes, inputs[i], imageData, modelFile, parameters)
           │        → ProcessingResult{ hash, output_buffers }
           └─ output_buffers → FileManager::SaveASync(...) per processing_.get_outputs()[k], IPFS dual-save,
                    hash → returned as std::vector<uint8_t>
```

Two load-bearing facts this design rests on, both broken by a render pass:

1. **Dispatch key is `DataType`, not `PassType`.** `m_processorFactories` is keyed by the *input's* `DataType` (`TEXTURE2_D`, `STRING`, …), populated once in `Init()`. `PassType` is checked only for JSON validation in `CheckProcessValidity()` and is never read again. There is no `PassType`-keyed table anywhere.
2. **One pass ⇄ one model ⇄ one input, addressed positionally.** `Process()`/`GetCidForProc()` assume `passes[i]` is the pass that owns `inputs[i]`, recovered via `GetInputIndex` on the model's `source` string. A render pass has *no* `model`, has *multiple* inputs bound via `pass.get_inputs()` (`PassIoBinding`, resolved by `input:`/`internal:`/`parameter:` prefix — a totally different resolution mechanism than `IoDeclaration`/`m_inputMap`), and needs a `pass.get_outputs()` (`PassIoBinding` with `output:`/`internal:` targets) rather than the top-level `processing_.get_outputs()` used today. The existing single positional index cannot express "this pass reads binding `vertexBuffer` from `input:mesh` and binding `indexBuffer` from `input:indices`."

**Consequence for this milestone's dispatch design:** `PassType`-keyed dispatch cannot bolt onto the *existing* `SetProcessorByName(DataType)` call without a parallel resolution path, because a render pass is identified and driven by *pass name + `PassIoBinding` list*, not by *input index + `IoDeclaration`*. Build the render path as a second, independent resolution branch inside `Process()`, not as a `DataType` alias.

### Target architecture (render path added)

```
ProcessingManager::Process(...)
    │
    ├─ Resolve which Pass this SubTask targets
    │     (today: purely via GetInputIndex(model.source); render subtasks carry
    │      no ModelNode — need a pass-name-keyed lookup, e.g. m_passMap["passName"],
    │      built in Init() alongside m_inputMap, mirroring its construction pattern)
    │
    ├─ switch (pass.get_type())
    │     case PassType::RENDER:
    │         → RenderProcessor path (new)
    │     default (existing DataType path):
    │         → SetProcessorByName(inputs[i].get_type()) → MNN processor (unchanged)
    │
    └─ RenderProcessor path:
          1. Resolve each PassIoBinding in pass.get_inputs() to a buffer:
                "input:name"    → fetch via FileManager (same GetSubCidForProc mechanism)
                "internal:name" → produced by an earlier pass in this same job (new: an
                                  internal-buffer table scoped to one ProcessingManager::Process() call)
                "parameter:name"→ processing_.get_parameters() (already resolved elsewhere for
                                  StringMNN's tokenizerMode pattern — reuse that lookup helper)
          2. RenderProcessor::StartProcessing(...) (render-shaped signature, see below)
                a. Acquire/construct the render context (Vulkan instance/device/queue — see
                   "Render Context Ownership" below)
                b. Compile/load shader stages from pass.get_shader() (vertex+fragment; the
                   schema extension mentioned in PROJECT.md, not designed here)
                c. Upload vertex/index buffers from resolved PassIoBinding inputs
                d. Allocate offscreen render target(s) (color/depth attachment images) sized
                   per schema render-target config
                e. Record + submit command buffer; wait on fence (headless — no
                   surface/swapchain, no present)
                f. Read back render target into host memory (vkCmdCopyImageToBuffer +
                   host-visible staging buffer, or vkMapMemory if HOST_VISIBLE was used
                   for the target directly)
          3. Wrap readback bytes in the *same* ProcessingResult{ hash, output_buffers }
             shape MNN processors return — hash via existing sgprocmanagersha::sha256,
             output_buffers feeding the existing FileManager::SaveASync /
             IPFS-dual-save / output_locations code in Process() completely unchanged.
```

### Component Boundaries

| Component | Responsibility | Communicates With | Status |
|-----------|---------------|-------------------|--------|
| `ProcessingManager` (`ProcessingManager.cpp/hpp`) | Parses `SgnsProcessing` JSON, owns pass/input maps, dispatches to a processor, drives output save | `ProcessingProcessor` subclasses (via factory map), `FileManager`, `sgprocmanagersha` | **Modified** — add `PassType` switch in `Process()`, add pass-name lookup map, fix `ParseBlockSize()` type guard (separate concern already tracked) |
| `ProcessingProcessor` (`processing_processor.hpp`) | Abstract base: `StartProcessing(...) -> ProcessingResult` | Implemented by MNN_* and (new) `RenderProcessor` | **Modified or extended** — see interface discussion below |
| `MNN_Image`, `MNN_String`, … (existing) | Inference execution per `DataType` | MNN library, Vulkan (MNN-internal, fully encapsulated) | **Unmodified** |
| `RenderProcessor` (new) | Builds and executes one headless render pipeline from a schema `Pass` (render type); returns `ProcessingResult` | `VulkanRenderContext` (new), a vendored Vulkan rendering/utility library (schema/library selection out of this doc's scope), `FileManager` (via `ProcessingManager`, not directly) | **New** |
| `VulkanRenderContext` (new) | Owns the render-pass-family's `VkInstance`/`VkPhysicalDevice`/`VkDevice`/`VkQueue`, independent of MNN's | `RenderProcessor` instances | **New** |
| `ProcessingManager::CheckProcessValidity()` | Per-pass JSON structural validation | — | **Modified** — `PassType::RENDER` case needs to validate `pass.get_shader()` is present (mirroring the existing `INFERENCE` → `get_model()` check), matching the schema's own `allOf`/`if`/`then` requirement that render passes have a `shader` |
| `gnus-processing-schema.json` / `generated/*.hpp` (quicktype) | Schema source of truth for `Pass`, `ShaderConfig`, `PassIoBinding`, etc. | Regenerated into `SGProcessingManager/generated/` | **Modified** (schema extension is a separate milestone deliverable; not designed in this file) |
| `thirdparty/<new-vulkan-lib>` | Vendored permissive-license Vulkan renderer/utility helper (device/instance bootstrap, pipeline builder, or similar) | Consumed by `RenderProcessor`/`VulkanRenderContext` | **New** (library selection is a `STACK.md` concern, not this file) |

### Data Flow

```
schema Pass (type: render)
   │  name, shader{source,type,entry_point,uniforms}, inputs[](PassIoBinding), outputs[](PassIoBinding)
   ▼
ProcessingManager::Process()
   │  resolves pass by name (new pass-name map), branches on PassType::RENDER
   ▼
RenderProcessor::StartProcessing(pass, resolved_input_buffers, parameters)
   │
   ├─ Pipeline construction
   │     shader stages  ← compile/load SPIR-V from pass.shader (vertex + fragment)
   │     vertex/index buffers ← upload from PassIoBinding "input:"/"internal:" sources
   │     render target  ← allocate offscreen color (+ optional depth) image per schema render_target config
   │     descriptor/uniform data ← pass.shader.uniforms, resolved same way as PassIoBinding sources
   │
   ├─ Execution (headless — no VkSurfaceKHR, no swapchain, no vkQueuePresentKHR)
   │     record command buffer → vkQueueSubmit → vkWaitForFences
   │
   └─ Readback
         vkCmdCopyImageToBuffer → host-visible staging buffer → std::vector<char>
   ▼
ProcessingResult{ hash = sha256(readback_bytes), output_buffers = {names, [readback_bytes]} }
   ▼
ProcessingManager::Process() (unchanged from here down)
   │  same code path MNN results already use:
   ├─ FileManager::SaveASync(outputUrl, ...)     — save to IPFS/file per processing_.get_outputs()
   ├─ IPFS dual-save to local cache
   └─ returns processResult.hash  →  SubTaskResult.result_hash (proto), used by
      existing consensus/validation hashing exactly as inference results are today
```

**Key point:** everything *downstream* of `ProcessingResult` (hashing format, save/dual-save, `output_locations`, proto `SubTaskResult`) is reused completely unmodified — a render pass is just another producer of a `ProcessingResult`. Everything *upstream* of it (pass/input resolution) needs the new pass-name-keyed lookup because render passes are not addressable through the existing input-index positional trick.

## Patterns to Follow

### Pattern 1: PassType dispatch as a sibling branch, not a DataType alias

**What:** In `Process()`, dispatch on `pass.get_type()` first. Only fall through to the existing `SetProcessorByName(DataType)` / `m_processorFactories` mechanism for non-render pass types. Do not attempt to register `RenderProcessor` into `m_processorFactories` keyed by some synthetic `DataType` — the render path's inputs are plural and `PassIoBinding`-resolved, not singular and `IoDeclaration`-resolved, so it does not fit the factory's calling convention (`StartProcessing(chunkhashes, const IoDeclaration&, imageData, modelFile, parameters)`).

**When:** `PassType::RENDER` (and, by the same reasoning, `PassType::COMPUTE`, which shares the `shader_config`-shaped schema branch and will hit the same mismatch later).

**Example (illustrative — actual factory/table wiring is an implementation detail for planning):**
```cpp
// In ProcessingManager::Process(), after resolving `pass` by name:
switch (pass.get_type())
{
    case PassType::RENDER:
    {
        auto renderResult = RunRenderPass(ioc, pass, chunkhashes, parameters);
        // renderResult is a ProcessingResult — feed into the existing
        // output_buffers/FileManager block unchanged.
        break;
    }
    default:
    {
        // existing DataType-keyed m_processorFactories path, unchanged
        break;
    }
}
```

### Pattern 2: A render-specific method on `ProcessingProcessor`, or a parallel interface — recommend the latter

**What:** `ProcessingProcessor::StartProcessing(chunkhashes, const IoDeclaration&, imageData, modelFile, parameters)` is inference-shaped: exactly one `IoDeclaration` (one input), one model-file buffer. A render pass needs: the `Pass&`/`ShaderConfig&` itself, an ordered list of resolved input buffers (one per `PassIoBinding`, each carrying its own type/format), and no model file at all.

Two options were weighed:
- **(a) Overload the base interface** — add a second pure-virtual `StartProcessing(chunkhashes, const Pass&, std::vector<ResolvedBinding>&, parameters)` to `ProcessingProcessor`, defaulted to throw/assert in the MNN subclasses that don't implement it.
- **(b) A parallel interface**, e.g. `RenderProcessorBase`, that does *not* inherit `ProcessingProcessor` at all, and is invoked from its own branch in `Process()` (Pattern 1) rather than through `m_processorFactories`.

**Recommendation: (b).** `ProcessingProcessor` is consumed today only through `m_processorFactories`/`SetProcessorByName`/`m_processor` — all keyed and typed around the single-`IoDeclaration` inference shape. Forcing a second signature onto that interface means every existing MNN_* subclass gets a dead-code override, and `m_processor` (a single `unique_ptr<ProcessingProcessor>`) would need to hold either shape ambiguously. A parallel, render-specific interface (own header, own factory map keyed by pass name or by `ShaderType`/render-target-kind if multiple render pipeline "flavors" emerge later) keeps the inference path completely untouched and gives the render path a signature that actually matches its data (a `Pass`, not an `IoDeclaration`).

**Instead of `m_processor` (singular member):** introduce a second, separate member (e.g. `std::unique_ptr<RenderProcessorBase> m_renderProcessor`) or, simpler for a first cut, construct a `RenderProcessor` instance locally inside the `PassType::RENDER` branch of `Process()` — it does not need to be a long-lived class member like `m_processor` is, since (unlike MNN's stateful session model) each render pass execution is expected to be a self-contained construct-pipeline → execute → readback → destroy sequence per subtask.

### Pattern 3: Per-`RenderProcessor`-instance Vulkan device, shared instance-level context

**What:** Two axes of ownership need separating:
1. **`VkInstance`** — process-wide, expensive to create, holds no per-job state. Own it in a small singleton/lazily-initialized `VulkanRenderContext` (analogous in spirit to `FileManager::GetInstance()`'s singleton pattern already used elsewhere in this same call path), created once, guarded by its own mutex during the one-time `vkCreateInstance`/`vkCreateDevice` calls.
2. **`VkDevice`/`VkQueue`** — also process-wide is fine *if* the node only ever runs one render pass at a time (true today: `ProcessingCoreImpl` already serializes subtask processing via `IncProcessingSubTaskCount()`/`max_processing_subtask_count_`, and the *existing* `mnn_vulkan_mutex` in `processing_processor_mnn_image.cpp:114` shows the codebase already treats "one Vulkan init at a time, process-wide" as an accepted constraint). Do not create a new `VkDevice` per `RenderProcessor` instance — device creation is comparatively heavyweight and per-job device churn would dominate short render passes.
3. **Command pools / command buffers / descriptor pools / the render target images themselves** — these *are* per-render-pass, i.e. own them on the `RenderProcessor` instance (or a short-lived helper it owns), reset/destroyed after each `StartProcessing()` call. This is the resource tier that legitimately varies per schema `Pass`.

**Why not a fully independent instance/device per `RenderProcessor` (full isolation)?** It is *safer* in isolation (zero shared mutable state) but the milestone's own context flags MNN's Vulkan init as process-wide-mutex-serialized already, and Vulkan instance/device creation cost is nontrivial (driver JIT, ICD enumeration) — paying that cost per subtask would regress the very short single-pass timings this pipeline is optimized for. Because MNN's Vulkan usage is fully encapsulated with **no exposed handles**, there is no *technical* requirement to interop share objects with MNN's context — the "must stay fully separate" constraint from the milestone context is satisfied automatically by MNN never exposing anything to share with. The design choice here is therefore purely about the new render context's *own* internal reuse, not about coordinating with MNN.

**Recommendation:**
```
VulkanRenderContext (process-wide singleton, lazily constructed, own init mutex)
    VkInstance   — created once
    VkPhysicalDevice — selected once (headless-capable: no WSI/presentation
                       queue family requirement, just a GRAPHICS-capable queue)
    VkDevice     — created once
    VkQueue      — fetched once from the device

RenderProcessor (constructed per Pass execution, short-lived)
    holds a reference/shared_ptr to VulkanRenderContext (not its own instance/device)
    owns: command pool, command buffer(s), descriptor pool, pipeline layout/pipeline,
          render target image(s) + image views + framebuffer, staging/readback buffer
    all of the above destroyed when the RenderProcessor is destroyed (RAII, one per
    StartProcessing() call — matches the "construct → execute → readback → destroy"
    lifecycle described in Pattern 2)
```

If profiling later shows the singleton's implicit serialization (only one render pass in flight at a time on a given node, mirroring the existing `mnn_vulkan_mutex` pattern) is a throughput bottleneck, the escape hatch is a **pool of devices** behind the same `VulkanRenderContext` facade (still process-wide-owned, still not per-`RenderProcessor`) — not one device per instance. Do not build that pool preemptively; it's unjustified complexity until there's a measured need, and it is not a decision this milestone needs to make.

## Anti-Patterns to Avoid

### Anti-Pattern 1: Reusing `GetInputIndex`/positional `passes[i]` lookup for render passes

**What:** Extending the current `passes[index]` positional trick (where `index` comes from `GetInputIndex` on a *ModelNode's* source) to somehow also resolve which pass is the render pass.

**Why bad:** That trick only works because today every pass has exactly one model with one `input:` source, and pass-list-position happens to equal input-list-position. A render pass may have zero, one, or several `PassIoBinding` inputs with no `ModelNode` at all — there is nothing for `GetInputIndex` to be called *with*. Trying to force-fit it produces silent misalignment bugs (wrong pass executed) rather than a clean failure.

**Instead:** Add an explicit pass-name map (`m_passMap: name → index into processing_.get_passes()`), built in `Init()` the same way `m_inputMap` already is (lines 121-126 of `ProcessingManager.cpp`), and have the caller (`ProcessingCoreImpl`/subtask JSON) carry a pass-name reference for render/compute subtasks instead of (or alongside) the `ModelNode` JSON it carries today for inference subtasks.

### Anti-Pattern 2: Creating a `VkInstance`/`VkDevice` per `RenderProcessor` construction

**What:** Mirroring the "per-processor-instance" ownership that would seem symmetrical with the `RenderProcessor : per-Pass-execution` lifecycle from Pattern 2/3.

**Why bad:** Vulkan instance/device creation is the most expensive part of the Vulkan startup sequence (ICD/layer enumeration, driver capability negotiation). Paying it on every subtask defeats the purpose of a distributed *chunked* processing pipeline built around many small, fast subtask executions (see `ProcessTaskSplitter::SplitTask`'s per-chunk subtask model).

**Instead:** Singleton/shared `VulkanRenderContext` for instance+device+queue (Pattern 3); per-execution ownership only for command buffers, descriptor sets, and the render target images themselves.

### Anti-Pattern 3: Forcing render output through the `IoDeclaration`-shaped output loop unchanged

**What:** Assuming `processing_.get_outputs()` (top-level `IoDeclaration` list) is sufficient to route render target readback to its save location without checking `pass.get_outputs()` (`PassIoBinding`, resolves via `output:`/`internal:` targets).

**Why bad:** The schema explicitly gives *passes* their own `outputs` (`PassIoBinding[]`) distinct from the job-level `outputs` (`IoDeclaration[]`) used by `Process()`'s save loop today. A render pass's target may be an `internal:` buffer consumed by a *later* pass (e.g., a render pass feeding a subsequent `data_transform` or `inference` pass) rather than a job-level output at all — multi-pass jobs are visibly anticipated by the schema (`data_transforms` array on `Pass`, `internal:` prefix throughout) even though today's `ProcessingManager::Process()` only ever executes one pass per call.

**Instead:** When a render pass's `PassIoBinding` output target is `internal:*`, keep the readback bytes in an in-memory intra-job buffer table (scoped to one `Process()` invocation, or eventually one multi-pass job if/when `Process()` grows to iterate `processing_.get_passes()` rather than run a single pass) rather than routing it through `FileManager::SaveASync`. Only route to `FileManager`/output save when the binding target resolves to a job-level `output:` name matching an entry in `processing_.get_outputs()`.

## Scalability Considerations

| Concern | At 1 render pass/job (this milestone's E2E proof) | At multi-pass jobs (render → inference chains) | At high concurrent job volume |
|---------|--------------------------------------------------|--------------------------------------------------|-------------------------------|
| Vulkan context lifetime | Singleton `VulkanRenderContext`, created lazily on first render pass | Unchanged — still one process-wide instance/device | May need the device-pool escape hatch from Pattern 3 if serialization becomes measured bottleneck |
| Serialization | Fine as-is — `ProcessingCoreImpl` already gates subtask concurrency via `max_processing_subtask_count_`; mirrors existing `mnn_vulkan_mutex` precedent | `RunRenderPass` must not hold the process-wide render-context init mutex across the *entire* pipeline execution — only around one-time instance/device creation, not per-frame submission, or every subsequent render pass job serializes behind it unnecessarily | Same |
| Internal buffer passing between passes | N/A (single pass) | Needs the `internal:`-scoped buffer table described in Anti-Pattern 3 | Needs a bound on how much intermediate GPU/host memory a single multi-pass job can hold resident — not addressed by this milestone |
| Render target memory | One small offscreen target per subtask, freed on `RenderProcessor` destruction | Same, but device-local intermediate targets for `internal:`-chained passes could stay GPU-resident rather than round-tripping through host memory each hop | Would need target-size/format validation added to `CheckProcessValidity()`'s `RENDER` case (currently a total no-op — this milestone's fix should at minimum validate `pass.get_shader()` presence, matching `INFERENCE`'s `get_model()` check) |

## Build Order (dependency-ordered)

1. **Schema extension** (`gnus-processing-schema.json` render_target/framebuffer config, vertex/index buffer bindings, multi-stage shader; regenerate `generated/*.hpp`) — everything downstream reads these generated types (`Pass::get_shader()`, `PassIoBinding`, a new render-target-config type), so this must land first. *(Detailed schema design is out of this file's scope — flagged here only for ordering.)*
2. **`ParseBlockSize()` type guard** — independent of the render path itself, but must land before any real render/compute pass reaches `ParseBlockSize()` in practice, or it crashes on `pass.get_model().value()` for a pass with no model. Cheap, no dependencies on step 1's shape (only needs a `pass.get_type()` check), safe to do in parallel with step 1.
3. **`PassType` dispatch plumbing in `ProcessingManager::Process()`** — the pass-name lookup map (`m_passMap`) and the `switch(pass.get_type())` branch point (Pattern 1). Depends on step 1 only insofar as the render branch's *body* references new schema fields; the branch/dispatch *scaffolding* itself can be built and tested with a stub render handler before the Vulkan work exists. **Also update `CheckProcessValidity()`'s `RENDER` case** in this step to validate `pass.get_shader()` is present (currently silently accepts a render pass with no shader at all).
4. **Vulkan render context setup** (`VulkanRenderContext`: instance/device/queue singleton, Pattern 3) — depends on the vendored Vulkan rendering/utility library selection (a `STACK.md` concern) being in place, and on `Vulkan-Headers`/`Vulkan-Loader` (already vendored). Independent of steps 1-3; can be developed/unit-tested in isolation (e.g. a standalone "create headless device, clear a framebuffer, read back a solid color" smoke test) before wiring into `ProcessingManager` at all.
5. **`RenderProcessor` implementation** — depends on steps 1 (schema types to read), 3 (dispatch branch to be called from), and 4 (context to execute against). This is the pipeline-construction → execution → readback logic (Pattern 2's parallel interface).
6. **End-to-end proof** (a real render pass definition executes through the distributed pipeline, produces a verifiable output hash) — depends on all of the above, plus confirming the readback bytes flow correctly through the *unchanged* `ProcessingResult`/`FileManager::SaveASync`/hash-return path already exercised by MNN passes today.

**Parallelizable subset:** steps 2 and 4 have no dependency on each other or on step 1's exact schema shape and can proceed concurrently with step 1. Step 3's scaffolding (dispatch branch + pass-name map + validity-check fix) can also start before step 1 is fully finalized, using a stub/no-op render handler, then be filled in once steps 1, 4, and 5 land.

## Sources

- `SuperGenius/SGProcessingManager/src/processingbase/ProcessingManager.cpp` (primary source, read in full) — HIGH confidence, verified against live repo at commit checked out in this workspace
- `SuperGenius/SGProcessingManager/include/processingbase/ProcessingManager.hpp` — HIGH confidence
- `SuperGenius/SGProcessingManager/include/processors/processing_processor.hpp` — HIGH confidence
- `SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_image.cpp` (mutex pattern at line 114, confirms process-wide MNN Vulkan-init serialization) — HIGH confidence
- `SuperGenius/SGProcessingManager/gnus-processing-schema.json` and `SGProcessingManager/generated/{Pass,PassType,PassIoBinding,ShaderConfig,ShaderType,Uniform,IoDeclaration,SgnsProcessing,DataType,ModelConfig}.hpp` — HIGH confidence, quicktype-generated from schema, read directly
- `SuperGenius/src/processing/impl/processing_core_impl.cpp` (caller context: `ProcessSubTask`, subtask concurrency gating via `max_processing_subtask_count_`) — HIGH confidence
- `SuperGenius/SGProcessingManager/src/processing_tasksplit.cpp` (subtask/chunk splitting model, confirms per-chunk subtask granularity) — HIGH confidence
- `SuperGenius/SGProcessingManager/src/processors/CMakeLists.txt` and `SuperGenius/src/processing/CMakeLists.txt` (confirms `Vulkan::Vulkan` is already a public link target for both `SGProcessors` and `processing_service` today, and MoltenVK is vendored for Apple builds — i.e., a Vulkan loader/headers dependency already threads through this exact build graph) — HIGH confidence
- `thirdparty/Vulkan-Headers`, `thirdparty/Vulkan-Loader` (present as vendored submodules; no VMA/shaderc/glslang/SPIRV-Cross/vk-bootstrap vendored yet — confirms a rendering/utility library still needs selecting, out of scope for this file) — HIGH confidence
- `.planning/PROJECT.md` "Workstream: sgproc-render" section — HIGH confidence (primary project context, required reading)
