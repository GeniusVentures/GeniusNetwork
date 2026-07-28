# Final Rendering Backend Decision

**Decided:** 2026-07-28
**Status:** LOCKED for milestone v1.0 (sgproc-render)

## Decision

Adopt **bgfx** (BSD-2-Clause) as the rendering abstraction for `PassType::RENDER`, with an explicitly-sequenced three-tier backend fallback chain:

1. **Vulkan (hardware)** — primary tier. `bgfx::RendererType::Vulkan`, headless (`platformData.nwh = NULL`). Confirmed genuinely swapchain-free on every platform Vulkan is enabled on (Linux, Windows, macOS via MoltenVK, Android) via direct read of `renderer_vk.cpp:1267`.
2. **OpenGL (hardware)** — secondary fallback, **Linux only**. `bgfx::RendererType::OpenGL` via EGL, which supports a genuine pbuffer-backed headless context (`glcontext_egl.cpp`). **Never attempted on Windows** (WGL requires a real window or externally-supplied context — no auto pbuffer fallback exists in bgfx's own WGL path, confirmed via `glcontext_wgl.cpp:114-303`) or **macOS** (bgfx does not enable a default OpenGL backend there — `config.h`).
3. **Vulkan-via-SwiftShader (software)** — tertiary/CPU-only tier when no hardware Vulkan or (Linux) OpenGL device is found. Still `bgfx::RendererType::Vulkan` under the hood — SwiftShader is a software Vulkan ICD, not a distinct bgfx renderer type. Likely selected via `bgfx::Init::vendorId = BGFX_PCI_ID_SOFTWARE_RASTERIZER`, but this mechanism's end-to-end effect on physical-device selection has **not** been traced/verified yet — flagged as an implementation-time spike, not assumed to "just work."

All three tiers must be **sequenced explicitly at the application level** (`bgfx::Init::fallback = false`) — bgfx's built-in fallback cascade is a fixed per-platform score table (e.g. prefers D3D11/D3D12 over OpenGL on Windows) with no concept of headless-capability or software/hardware distinction, and must not be relied upon.

MoltenVK (already vendored) remains the Vulkan-on-Metal implementation underneath bgfx's Vulkan backend on macOS/iOS — unchanged from how MNN already uses it today.

## What this replaces

The original Stack research (`STACK.md`) recommended a **hand-rolled `RenderProcessor` on raw Vulkan** (vk-bootstrap + VMA + Google's `shaderc`), explicitly rejecting all rendering engines — including bgfx — as unnecessary overhead for a single schema-declared pipeline. That evaluation was scored against headless-Vulkan-support + license + API ergonomics alone, not multi-backend fallback.

This decision **supersedes** that recommendation:

| Original (STACK.md) | Now (this decision) | Why |
|---|---|---|
| `vk-bootstrap` for instance/device bootstrap | Dropped — bgfx owns instance/device/queue creation internally | bgfx's `bgfx::init()` handles this per-backend; a second bootstrap layer would be redundant |
| VMA for buffer/image allocation | Dropped — bgfx owns buffer/texture allocation via its own API (`bgfx::createVertexBuffer`, `createTexture`, etc.) | Same reason — bgfx already abstracts this |
| Google's `shaderc` (GLSL→SPIR-V) | Replaced by **bgfx's own `shaderc` tool** (confusingly, an identically-named but unrelated tool) | bgfx shaders are authored once in bgfx's own shader dialect and cross-compiled by bgfx's toolchain to whichever backend format the active tier needs (SPIR-V, GLSL, HLSL, Metal) — job authors do not pick a `ShaderType` per target backend the way the original schema design assumed |
| Raw `vkCmd*`/`vkCreate*` calls in `RenderProcessor` | `RenderProcessor` built against bgfx's frame/submit/blit API (`bgfx::submit`, `bgfx::blit`, `bgfx::readTexture`, etc.) | Full API-surface change |
| Single Vulkan-only path | Explicit 3-tier fallback chain (Vulkan hw → OpenGL Linux-only → Vulkan-via-SwiftShader) | This is the entire point of the reconsideration — MNN-parity graceful degradation |

## Reasoning trail (chronological)

1. **`STACK.md`** — first pass, Vulkan-only raw approach recommended; bgfx and 3 other engines evaluated and rejected on headless/license/ergonomics grounds alone.
2. **`RENDER-BACKEND-DECISION.md`** — user asked for MNN-style graceful backend fallback (not just "pick one Vulkan path"). Found: no C++ rendering engine (bgfx included) offers a genuine app-level CPU-rasterizer *choice* — the only real CPU fallback exists one layer down, at the Vulkan-ICD level (SwiftShader/lavapipe). Reaffirmed hand-rolled-Vulkan-only + SwiftShader-ICD as sufficient, since bgfx's engine-level fallback (Vulkan↔OpenGL↔D3D↔Metal) doesn't solve the true no-GPU case any better than raw Vulkan + an ICD swap does.
3. **User counter-proposal** — pointed out that bgfx's real Vulkan↔OpenGL app-level tier switching still has value (reduces duplicated pipeline-construction code across two real GPU APIs instead of hand-rolling both), with SwiftShader still covering the final CPU-only tier underneath. Flagged a specific risk: `RENDER-BACKEND-DECISION.md` cited open bgfx issues suggesting the Vulkan backend might not be genuinely headless.
4. **`BGFX-HEADLESS-VERIFICATION.md`** — dedicated verification spike, primary-source-grounded (actual bgfx source reads + full GitHub issue threads via API, not search snippets). Found the headless-Vulkan concern was unfounded (issues were old, OpenGL-scoped, and predate both the current Vulkan headless code and the `examples/50-headless` example added 2025-11-01). Found the real window requirement is OpenGL-only and further scoped to Windows/WGL specifically (not Linux/EGL, not macOS since bgfx doesn't default-enable GL there).
5. **This decision** — full pivot to bgfx given (4)'s findings resolve the blocking concern from (3), and the user confirmed accepting the full architectural consequence (not just an additive OpenGL tier) in (2)'s counter-proposal discussion.

## Licensing

| Component | License | Verified |
|---|---|---|
| bgfx | BSD-2-Clause | Direct `LICENSE` fetch |
| SwiftShader | Apache-2.0 | Direct `LICENSE` fetch |

Both non-GPL, consistent with the project's permissive-license constraint. No change to the project's existing all-permissive `thirdparty/` posture.

## Open technical questions carried into implementation (not resolved by research — flagged for the relevant phase)

- Whether `BGFX_PCI_ID_SOFTWARE_RASTERIZER` actually forces bgfx's Vulkan physical-device selection onto the SwiftShader ICD end-to-end (not traced past the constant's existence/documentation) — needs an experimental check before depending on it as the sole software-tier selection mechanism.
- The exact downstream failure mode if the OpenGL tier were ever attempted on Windows despite the exclusion (silent `NULL` context per `glcontext_wgl.cpp`, not a clean init failure) — moot if the exclusion is enforced, but worth a defensive check.
- Whether same-node determinism (a node's tier is chosen once at startup/capability-detection and stays fixed for that node's lifetime) needs an explicit guard against tier re-selection mid-operation — the tier decision should be pinned once, not re-evaluated per job.

## Consequence for schema design (Phase 1)

The `ShaderType` enum's original meaning (`glsl|hlsl|metal|spirv` — job author picks a format matching their target backend) no longer fits: bgfx job authors write **once**, in bgfx's own shader dialect, and bgfx's toolchain cross-compiles per active backend transparently. Phase 1's schema work must reconcile this directly — either re-scoping `ShaderType` to represent "bgfx shader source" (single value) or accepting pre-compiled bgfx shader binaries as the pass input. This is now an open design question for Phase 1, not a settled requirement (see REQUIREMENTS.md SCHEMA-04, revised).

## Vendoring

bgfx and SwiftShader are added as new `thirdparty/` git submodules, built via the existing monolithic `CommonBuildParameters.cmake`/`CommonTargets` CMake convention — the same mechanism already used for Vulkan-Headers, Vulkan-Loader, and MoltenVK.

---
*Consolidates: STACK.md, RENDER-BACKEND-DECISION.md, BGFX-HEADLESS-VERIFICATION.md*
