# Feature Research

**Domain:** Headless/offscreen Vulkan render-pass execution as a distributed-compute "job" in SGProcessingManager
**Researched:** 2026-07-28
**Confidence:** MEDIUM (Vulkan mechanics are well-established/HIGH-confidence patterns; verifiable-render-output policy is genuinely unsettled territory across the industry — MEDIUM/LOW)

> Scope note: this covers ONLY the new `render` PassType capability — a headless graphics job that builds a pipeline from schema config, executes a render pass with no window/swapchain, and produces a verifiable (hashed) output through the same pipeline `inference`/`retrain` results already use. It does not re-research the existing `data_transform`, `pass_io_binding`, or MNN-dispatch mechanisms themselves — only how a render pass extends/interacts with them. Schema extension itself (render_target/framebuffer, vertex/index buffer bindings, multi-stage shader config) is separately scoped; this file notes where features *depend* on that work without designing it.

## Feature Landscape

### Table Stakes (Users Expect These)

For a verifiable-compute render job, "users" = the schema author (job designer) and the network consuming hashed results. Missing any of these means the `render` PassType isn't a real capability yet — it stays the no-op stub it is today.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Offscreen framebuffer (color attachment only, manually-allocated `VkImage`/`VkImageView`, no swapchain) | This is a headless compute node — there is no display to present to; every comparable engine's "headless mode" starts here | LOW | Standard pattern (Sascha Willems' `offscreen.cpp` is the reference impl): render pass + framebuffer wrapping a device-local image instead of swapchain images. |
| Minimal 2-stage shader pipeline (vertex + fragment) | This is the floor for "a render pass" — matches the milestone's own framing ("multi-stage shader pipeline, vertex+fragment at minimum") | LOW–MEDIUM | Replaces the current single `shader_config` (source+entry_point+uniforms) for render passes; depends on the separately-scoped schema extension to express two shader stages instead of one. |
| Vertex/index buffer upload (staging → device-local) | Any non-trivial mesh needs vertex data on the GPU; staging-buffer upload is the only broadly-correct pattern on dedicated GPUs without resizable BAR | MEDIUM | Standard pattern: host-visible+coherent staging buffer → `vkCmdCopyBuffer` → device-local final buffer over a transfer-capable queue. Depends on the separately-scoped vertex/index buffer binding schema work. |
| Single-mesh render-to-texture (one draw call, one target) | The simplest possible "job" — proves the pipeline end-to-end before any compositing/multi-pass complexity | LOW–MEDIUM | This is the correct MVP scope per the milestone's own "table stakes" framing. |
| Depth testing (depth attachment + compare op) | Any mesh with concave geometry or multiple triangles needs correct occlusion, or the "render" is wrong, not just simple | LOW–MEDIUM | Cheap to add alongside the color attachment; skipping it only works for guaranteed-non-overlapping single-triangle jobs, which is too narrow to call a real capability. |
| `RenderProcessor` registered in the same processor-factory dispatch pattern as MNN processors | Consistency with the existing `inference`/`retrain`/DataType-factory dispatch is what makes this a first-class PassType instead of a special case | MEDIUM | This is explicitly the milestone's `ProcessingManager::Process()` PassType-dispatch task — render is the first *PassType-keyed* (not DataType-keyed) processor family. |
| Rendered output exposed as a `texture2D` consumable through existing `pass_io_binding` output wiring | The schema's `pass_io_binding` already models `texture1D/2D/3D/Cube` — the render job's output must slot into that, not invent a parallel output mechanism | LOW | Direct reuse of existing mechanism; the render-specific work is only the readback (`vkCmdCopyImageToBuffer` with a layout transition to `TRANSFER_SRC_OPTIMAL`) that fills the buffer this output type wraps. |
| Uniform/parameter binding for shader constants (e.g. MVP matrices) reusing `shader_config.uniforms` + `parameter:`-prefixed `pass_io_binding` refs | Any non-trivial vertex shader needs a model/view/projection matrix or similar; the schema already has a uniform-declaration mechanism | LOW–MEDIUM | Reuse, not new design — the render-specific piece is binding these into a `VkDescriptorSet`/push constants at pipeline-build time. |
| Deterministic, reproducible readback for hashing/verification | The milestone's own success criterion is "a rendered image hash" — if two runs of the same job on the same node don't hash identically, there is no verifiable output at all | MEDIUM–HIGH | **Caveat (MEDIUM confidence):** exact bit-for-bit determinism is only safely assumable for a numerically-simple pipeline (flat/unlit shading, no blending, single fixed node/driver) — see Anti-Features and Gaps below. Same-node repeat-run determinism is much more tractable than cross-vendor determinism. |
| `ParseBlockSize()` type-guard fix for render/compute passes | Hard blocker already identified in `ProcessingManager.cpp` — unconditional `pass.get_model().value()` crashes on any pass with no `model` (which render/compute passes never have) | LOW | Precondition for *any* render pass reaching execution at all; not a "feature" so much as the entry ticket. |

### Differentiators (Competitive Advantage)

These extend the render capability beyond a single static mesh. Each should be sequenced *after* the table-stakes MVP proves the pipeline end-to-end, and several have a hard dependency on the separately-scoped schema extension.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Instancing (draw N copies of a mesh with per-instance data) | Lets a single job description do meaningfully more compute/verification work per dispatch — valuable for a distributed-compute network's throughput economics | MEDIUM | Native Vulkan feature (instanced vertex buffer + `gl_InstanceIndex`/`SV_InstanceID`); needs the vertex-buffer schema extension to express a per-instance step rate. |
| Multiple render targets (MRT) — e.g. simultaneous albedo/normal/depth output from one pass | Enables G-buffer-style jobs (useful if render output feeds a later inference pass, e.g. a synthetic-data-generation pipeline) | HIGH | **Hard dependency:** requires the render_target/framebuffer schema to express multiple color attachments — explicitly out of this research's scope, must be sequenced with/after that schema work. |
| Multi-pass / post-processing chains (pass N samples pass N-1's output texture) | The natural next step once render-to-texture exists — matches how virtually every real renderer (game engine, offline renderer) actually structures work | HIGH | Requires: (a) descriptor-set/sampler binding infrastructure not yet built for render passes, (b) inter-pass synchronization (image layout transitions/barriers between passes), (c) schema support for referencing a prior pass's output as an `input:` binding. All three cut across the separately-scoped schema work. |
| Texture sampling from an externally-supplied input texture (not just from a prior render pass) | Lets a render job consume texture data produced by, e.g., a `data_transform` step or an inference pass, reusing the existing `input:` prefix convention | MEDIUM–HIGH | Same descriptor/sampler infra as multi-pass chains, but simpler dependency graph (one hop, no inter-pass barrier chain). |
| Compute/inference → render interop (e.g. an MNN tensor output feeds a render pass's vertex or texture input) | Connects render into the broader processing pipeline rather than leaving it an isolated island — aligns with the project's `pass_io_binding`/`internal:` mechanism already existing for exactly this kind of cross-pass wiring | HIGH | The hard part isn't Vulkan — it's bridging an MNN tensor's memory layout into a Vulkan-compatible buffer/vertex-attribute layout without a redundant copy-and-reformat step; this is genuinely new plumbing. |
| Post-render `data_transform` reuse (e.g. normalize/color_convert applied to the rendered texture before output) | The generic `data_transform` mechanism already exists — wiring the render output through it as a post-step is mostly configuration, not new engine code | LOW–MEDIUM | This is the *cheapest* differentiator on this list precisely because it reuses an existing, already-built mechanism rather than adding new render-engine surface. |
| Configurable pipeline state (primitive topology beyond triangle list — line list/strip; cull mode; front-face winding) | Broadens what a render job description can express without adding new stages | LOW–MEDIUM | Straightforward Vulkan pipeline-state toggles exposed as schema fields; low risk once the base pipeline exists. |
| Alpha blending / transparency | Common expectation once anyone treats this as "a renderer" rather than a single-mesh compute primitive | MEDIUM | **Caution:** blending is order-dependent (draw order affects the accumulated result), which directly worsens the determinism/verification story — treat as a deliberate, flagged tradeoff, not a default-on feature. |

### Anti-Features (Commonly Requested, Often Problematic)

These are the "seems obviously needed because that's what renderers do" items that are actively wrong for a headless verifiable-compute job on a distributed processing node.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|------------------|-------------|
| Interactive/windowed rendering (swapchain, presentation, VSync) | "It's a renderer, shouldn't it show something?" | `SGProcessingManager` is explicitly headless — no window, no display, ever. A swapchain requires a `VkSurfaceKHR`/windowing-system integration this node will never have and can never validate in CI on a headless machine anyway | Offscreen framebuffer + `vkCmdCopyImageToBuffer` readback (already the table-stakes design) |
| Real-time frame pacing / continuous render loop at a target framerate | Habit carried over from game/interactive-rendering mental models | This is a discrete batch job (submit → execute once → return hashed result), not a continuous simulation; frame pacing has no meaning without a consumer watching frames in real time | Single-shot render → readback → hash → return, exactly like an `inference` pass today |
| Treating exact bit-for-bit pixel-hash equality (across arbitrary nodes/GPU vendors) as the sole verification method | "We hash inference outputs today, just hash the pixels the same way" | Floating-point arithmetic is non-associative and GPU rasterization/blending order is not guaranteed identical across vendors/drivers — well-documented failure mode in every distributed-rendering network researched (Render Network, Golem, iExec all had to solve this). Naive exact-hash verification will false-reject legitimate results from different hardware | Either (a) constrain verification to same-node repeat-execution determinism for now, or (b) adopt tolerance/redundancy-based verification (spot-check re-render + similarity metrics, à la Golem's Blender verification work) if cross-node exact-hash isn't achievable — this is a policy decision the milestone needs to make explicitly, not assume away |
| Full 3D-engine feature surface (skinning/animation, physics, multi-light PBR shading models, scene graphs) | "Real renderers have these" | This is a verifiable-compute primitive parallel to `inference`, not a game engine; every one of these adds shader/pipeline complexity and non-determinism surface for no corresponding value to the distributed-compute use case | Keep the shader-driven pipeline minimal and schema-declared; anything fancier belongs in the shader source itself if a job author truly needs it, not in engine-level feature flags |
| User-facing shader hot-reload / live shader editing | Convenience during interactive development | Irrelevant for a headless batch job, and actively at odds with wanting a fixed, hashed shader source for reproducibility (Vulkan's precompiled SPIR-V is already a determinism *win* over source-level shader compilation — don't undo that by making shaders mutable at runtime) | Shader source is part of the immutable job/schema definition, same as a model file is for `inference` |
| Persistent/shared Vulkan context reused across unrelated concurrent jobs | Render-farm-style throughput optimization (amortize context setup cost) | Premature optimization that couples unrelated jobs' lifetimes and failure modes together before the single-job path even works; also complicates the "each job produces an independently verifiable result" story | Per-job Vulkan instance/device setup and teardown, matching the isolation model `inference`/`retrain` processors already use |
| Multisampling/anti-aliasing on by default | "Renders should look good" | MSAA resolve behavior is itself vendor/driver-variable, adding another non-determinism source right where the milestone needs the opposite | If ever needed, make it an explicit opt-in schema flag with the determinism tradeoff documented, not a default |

## Feature Dependencies

```
Offscreen framebuffer + minimal vertex+fragment pipeline (table stakes)
    └──requires──> Schema extension: multi-stage shader config (separately scoped)
    └──requires──> ParseBlockSize() type-guard fix (hard blocker, already identified)

Vertex/index buffer upload
    └──requires──> Schema extension: vertex/index buffer bindings (separately scoped)

Single-mesh render-to-texture
    └──requires──> Offscreen framebuffer + pipeline
    └──requires──> Vertex/index buffer upload
    └──enables──> Rendered output as texture2D via pass_io_binding (existing mechanism, reused not rebuilt)
        └──enables──> Deterministic readback + hashing (reuses existing result-hash/verification path)

RenderProcessor PassType dispatch
    └──requires──> ProcessingManager::Process() PassType-based dispatch (this milestone's own scope item)
    └──enables──> Single-mesh render-to-texture actually executing (vs. today's no-op stub)

Instancing ──requires──> Vertex/index buffer schema extension (per-instance step rate)

Multiple render targets (MRT) ──requires──> render_target/framebuffer schema extension (multiple color attachments)

Multi-pass chains
    └──requires──> Render-to-texture output (single-mesh MVP)
    └──requires──> Descriptor/sampler binding infra (new — not yet built for render passes)
    └──requires──> Schema support for a pass consuming a prior pass's output as input:

Texture sampling from external input ──requires──> Descriptor/sampler binding infra (shared prerequisite with multi-pass chains)

Compute/inference → render interop ──requires──> Buffer/tensor layout bridging between MNN tensor output and Vulkan buffer/vertex input (new plumbing, no existing mechanism covers this)

Post-render data_transform reuse ──enhances──> Single-mesh render-to-texture (cheap, reuses existing generic mechanism)

Alpha blending ──conflicts──> Deterministic/reproducible readback (order-dependent accumulation directly undermines hash stability)

Exact bit-for-bit cross-vendor verification ──conflicts──> Any feature beyond the numerically-simplest pipeline (blending, MRT compositing, multi-pass accumulation all compound floating-point non-associativity)
```

### Dependency Notes

- **Everything funnels through the separately-scoped schema extension first.** Vertex/index buffer bindings, multi-stage shader config, and (for MRT) multiple render-target attachments are all schema prerequisites this research deliberately did not re-design, but every table-stakes and differentiator feature above needs at least one of them landed first.
- **`pass_io_binding` and `data_transform` are reused, not rebuilt, for anything render-to-texture-and-out.** The render-specific new work is narrowly: building the Vulkan pipeline/buffers, executing the pass, and doing the `vkCmdCopyImageToBuffer` readback into a buffer shape the existing output binding already understands.
- **Descriptor/sampler binding is new, shared infrastructure two differentiators need.** Multi-pass chains and external-texture sampling both require it — sequence one as the vehicle that builds it, and the other becomes cheap.
- **Determinism policy is a cross-cutting blocker, not a feature to schedule.** Whether verification is exact-hash (same-node only) or tolerance/redundancy-based (cross-node) changes what "verifiable output" means for every feature on this list — this should be resolved as an early architecture/pitfall decision, not discovered late. Flagging for `PITFALLS.md`/`ARCHITECTURE.md`, not resolving it here.

## MVP Definition

### Launch With (v1)

The smallest slice that turns `PassType::RENDER` from a no-op stub into a real, executable, verifiable job — matching the milestone's own "end-to-end proof" criterion.

- [ ] `ParseBlockSize()` type-guard fix — nothing else can be tested without this
- [ ] `RenderProcessor` registered via `PassType`-keyed dispatch in `ProcessingManager::Process()`
- [ ] Offscreen framebuffer (single color + depth attachment, no swapchain)
- [ ] Minimal vertex+fragment shader pipeline (fixed pipeline state: triangle list, back-face cull, no blending)
- [ ] Vertex/index buffer upload via staging → device-local pattern
- [ ] Uniform binding (MVP matrices) reusing `shader_config.uniforms` + `parameter:` refs
- [ ] Rendered output readback into a `texture2D`-shaped buffer consumable via existing `pass_io_binding` output
- [ ] Same-node deterministic hash of the readback buffer, verified via repeat execution (not cross-vendor) — proves the "verifiable output" end-to-end claim without prematurely committing to a cross-node verification policy

### Add After Validation (v1.x)

- [ ] Configurable pipeline state (topology, cull mode, front-face winding) — trigger: first job description that needs something other than the MVP's fixed defaults
- [ ] Instancing — trigger: a job needs repeated-mesh throughput and the vertex-buffer schema extension has landed
- [ ] Post-render `data_transform` reuse on the rendered texture — trigger: first consumer wants normalize/color_convert applied to render output before returning it
- [ ] Texture sampling from an externally-supplied input texture — trigger: first job needs a render pass to consume a texture that isn't itself a prior render pass's output

### Future Consideration (v2+)

- [ ] Multi-pass/post-processing chains — defer until descriptor/sampler infra and inter-pass schema support both exist; genuinely the next big lift, not incidental
- [ ] Multiple render targets (MRT) — defer until the render_target/framebuffer schema extension supports multiple color attachments
- [ ] Compute/inference → render interop — defer until there's a concrete job that needs it; the buffer-layout bridging work shouldn't be built speculatively
- [ ] Alpha blending / transparency — defer and treat as an explicitly-flagged, opt-in tradeoff against determinism, not a default capability
- [ ] Cross-node tolerance/redundancy-based verification (Golem/Render-Network style spot-check + similarity metrics) — only needed if/when render jobs must be verified across heterogeneous node hardware; same-node determinism suffices for the v1 proof

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| `ParseBlockSize()` fix | HIGH (blocker) | LOW | P1 |
| `RenderProcessor` PassType dispatch | HIGH | MEDIUM | P1 |
| Offscreen framebuffer + vertex+fragment pipeline | HIGH | LOW–MEDIUM | P1 |
| Vertex/index buffer upload | HIGH | MEDIUM | P1 |
| Render-to-texture output via existing `pass_io_binding` | HIGH | LOW | P1 |
| Same-node deterministic hash/verification | HIGH | MEDIUM–HIGH | P1 |
| Depth testing | MEDIUM–HIGH | LOW–MEDIUM | P1 |
| Uniform/parameter binding | MEDIUM–HIGH | LOW–MEDIUM | P1 |
| Configurable pipeline state | MEDIUM | LOW–MEDIUM | P2 |
| Post-render `data_transform` reuse | MEDIUM | LOW–MEDIUM | P2 |
| Instancing | MEDIUM | MEDIUM | P2 |
| Texture sampling from external input | MEDIUM | MEDIUM–HIGH | P2 |
| Multi-pass chains | MEDIUM–HIGH (long-term) | HIGH | P3 |
| Multiple render targets (MRT) | MEDIUM (long-term) | HIGH | P3 |
| Compute/inference → render interop | MEDIUM (speculative) | HIGH | P3 |
| Alpha blending | LOW–MEDIUM | MEDIUM | P3 |
| Cross-node tolerance-based verification | LOW now / HIGH if network heterogeneity matters | HIGH | P3 |

**Priority key:**
- P1: Must have — this is the render-pass MVP that satisfies the milestone's end-to-end proof
- P2: Should have, natural next slice once MVP is proven
- P3: Nice to have, defer until a concrete job/consumer needs it

## Competitor Feature Analysis

Comparable systems here are distributed/decentralized rendering and compute networks and traditional render-farm job schedulers — the closest available analogues to "a render pass as a discrete, verifiable job on a distributed compute node."

| Feature | Render Network (RNDR) | Golem / iExec | Traditional render farms (studio/cloud) | Our Approach |
|---------|------------------------|----------------|-------------------------------------------|--------------|
| Job submission | Standardized scene package (`.orbx`), payment escrowed in a smart contract before execution | Task submitted to network; consumer sets required reliability/redundancy level | Scene uploaded to shared storage, scheduler splits frames across a node fleet | Schema-defined `render` pass submitted through the same job pipeline as `inference`/`retrain`, no new submission path |
| Result verification | "Proof of Render" — other nodes spot-check/re-render and compare via consensus before payment releases | Redundant computation (send to >1 node, compare) or local partial recompute by the consumer; iExec scales redundancy to requested reliability | Typically trusted infrastructure (no adversarial verification needed — it's the studio's own farm) | Reuse existing hashed/verified result path from `inference`; **open question** whether same-node exact-hash is sufficient or cross-node tolerance/redundancy is eventually needed (see Gaps) |
| Handling of GPU non-determinism | Implicitly assumed by using spot-check/consensus rather than exact match | Golem explicitly rejected exact hash matching for Blender renders — built a perceptual-similarity + ML classifier pipeline instead, because bit-exact cross-node output isn't achievable | N/A — single trusted farm, no cross-node consistency requirement | Constrain v1 to same-node repeat-execution determinism; defer a cross-node tolerance policy to a future milestone rather than under-solving it now |
| Job structure | Full scene description (complex, artist-facing) | Arbitrary task (gWASM, general compute) | Full scene/frame per job | Deliberately minimal: single mesh, fixed pipeline state, schema-declared — not scene-authoring, a compute primitive |
| Multi-pass/compositing | Handled inside the renderer (OctaneRender), opaque to the network layer | N/A (general compute, not render-specific) | Common (beauty pass + volumetric pass on different hardware, composited after) | Deferred (P3) — requires new descriptor/sampler infra and schema support not yet built |

## Sources

- Sascha Willems' Vulkan offscreen rendering example (`SaschaWillems/Vulkan`, `examples/offscreen/offscreen.cpp`) — reference pattern for framebuffer/render-pass-without-swapchain setup — MEDIUM (web, cross-corroborated by multiple independent Vulkan tutorial sources on the render-pass/framebuffer/readback pattern)
- Vulkan-Tutorial / KhronosGroup `Vulkan-Tutorial` staging-buffer chapter — staging → device-local vertex/index buffer upload pattern — MEDIUM (web, corroborated across vulkan-tutorial.com, KhronosGroup's official tutorial repo, and Rust ports of the same tutorial)
- Render Network (RNDR) public documentation/explainers (CoinMarketCap, Messari, CoinGecko overviews) — job submission via escrow + "Proof of Render" spot-check verification model — MEDIUM (web, corroborated across multiple independent explainer sources)
- Golem Network blog — ["Verification of rendering results in Blender: nondeterminism and machine learning"](https://blog.golem.network/verification-of-rendering-results-in-blender-a-not-so-short-story-about-nondeterminism-and-machine-learning/) — concrete case study on why exact-hash verification fails for distributed rendering and what a perceptual/tolerance-based alternative looks like — MEDIUM (single detailed first-party source, directly on-topic)
- Golem gWASM redundancy-verification blog post, iExec public documentation summaries — redundant-computation verification model for general decentralized compute — MEDIUM (web, corroborated across Golem and iExec independently converging on the same redundancy pattern)
- Google Cloud Architecture Center, SuperRenders/render-farm technical guides — traditional render-farm job scheduler structure (asset sync, frame-splitting, pre/post-flight hooks, hybrid CPU/GPU pass routing) — MEDIUM (web, corroborated across independent render-farm technical writeups)
- Floating-point non-associativity / GPU non-determinism literature (arXiv: optimistic verification, tolerance-aware verification, non-determinism in GPU inference) — LOW–MEDIUM (web search summaries of arXiv papers on verifiable ML inference; directly analogous to but not specific to graphics rasterization — treated as strong circumstantial evidence, not graphics-specific confirmation)
- SwiftShader/Mesa Lavapipe (software Vulkan rasterizers used for deterministic CI/headless testing) — LOW (web, single-topic search; noted as a possible mitigation path for same-hardware-class determinism, not independently verified against this project's needs)
- SGProcessingManager source (`ProcessingManager.cpp`, `gnus-processing-schema.json`) — direct codebase read, confirming `PassType::RENDER`'s current no-op status, the existing `shader_config`/`pass_io_binding`/`data_transform` schema shapes, and the `ParseBlockSize()` blocker context — HIGH (primary source, first-party code)

---
*Feature research for: SGProcessingManager render-pass execution (sgproc-render workstream, v1.0)*
*Researched: 2026-07-28*
