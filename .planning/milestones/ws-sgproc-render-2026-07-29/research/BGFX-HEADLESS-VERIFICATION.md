# BGFX Headless Verification — Pitfalls & Findings

**Domain:** bgfx zero-window headless rendering capability (Vulkan backend vs. OpenGL backend), for the proposed sgproc-render three-tier fallback architecture (Vulkan hardware -> OpenGL -> SwiftShader software-Vulkan-ICD)
**Researched:** 2026-07-28
**Confidence:** HIGH — every core claim below is grounded in a direct primary-source read: bgfx's own `examples/50-headless/headless.cpp`, `src/renderer_vk.cpp`, `src/glcontext_wgl.cpp`, `src/glcontext_egl.cpp`, `src/config.h`, `src/bgfx.cpp`, `include/bgfx/bgfx.h` (fetched raw and read directly, not summarized from search snippets), plus the actual GitHub issue bodies and maintainer comments for #1974 and #1285 pulled via the GitHub REST API (not just issue titles). Nothing here is inferred from general bgfx reputation or forum hearsay.

## Verdict (read this first)

**(a) YES — bgfx's Vulkan backend has genuine, first-class, zero-window-handle headless support.** This is not a workaround, not a stub, and not disputed in current bgfx. `src/renderer_vk.cpp:1267` computes `const bool headless = NULL == g_platformData.nwh;` and threads that flag through actual instance/device setup: when headless, bgfx skips requesting `VK_KHR_SURFACE_EXTENSION_NAME` (instance extension, line 1374-1378) and `VK_KHR_SWAPCHAIN_EXTENSION_NAME` (device extension, line 2038-2042), and `SwapChainVK::create()` (line 7611, 7628-7631) returns immediately with no surface/swapchain object created at all when `_nwh == NULL`. This is real Vulkan-instance/device-extension-level headlessness, not merely "skip one API call." The rest of `RendererContextVK::init()` proceeds identically regardless of `headless` — a real `VkInstance`/`VkPhysicalDevice`/`VkDevice`/`VkQueue` is still created, pipelines still build, draw calls still execute; only the WSI presentation surface is ever skipped.

**(b) The window requirement is isolated to the OpenGL backend, and even there it is platform-specific — it is not a Vulkan problem, on any platform:**
- **Windows (WGL, bgfx's native/desktop-GL path):** genuinely requires a real window. `src/glcontext_wgl.cpp:114-303` — `GlContext::create()` has exactly two conditional blocks, both gated on `NULL != g_platformData.nwh`. If `nwh` is NULL, neither block executes, `m_context` stays NULL, and bgfx does nothing to create a GL context — it silently assumes "the assumption is that GL context was created by user (for example, using SDL, GLFW, etc.)" (the code's own comment, line 122-127). There is no pbuffer/dummy-context auto-creation fallback in bgfx's own WGL implementation for the `nwh == NULL` case.
- **Linux (EGL, bgfx's desktop-GL path since GLX was dropped from the current tree — no `glcontext_glx.cpp` exists anymore):** genuinely does **not** require a window. `src/glcontext_egl.cpp:311` computes `const bool headless = EGLNativeWindowType(0) == nwh;`, uses it to request `EGL_PBUFFER_BIT` instead of `EGL_WINDOW_BIT` when selecting an EGL config (line 424), and `SwapChainGL`'s constructor (line 153-179) calls `eglCreatePbufferSurface()` instead of `eglCreateWindowSurface()` when `_nwh == 0`. This is a genuine windowless path with no X server or Wayland compositor required.
- **macOS:** moot — `src/config.h:81-86` shows `BGFX_CONFIG_RENDERER_OPENGL` (desktop GL) defaults to enabled **only** on `BX_PLATFORM_LINUX` and `BX_PLATFORM_WINDOWS`. macOS's default backends are Metal and Vulkan-via-MoltenVK; bgfx does not ship a native macOS OpenGL context path in the current tree at all (no `NSOpenGL`/`CGL` reference anywhere in `renderer_gl.cpp`).

**(c) The user's proposed mitigation — skip the OpenGL tier on platforms where it requires a window (i.e., skip it on Windows), and rely on Vulkan (hardware) or a software Vulkan ICD there instead — is a clean, low-complexity, application-level fix with no bgfx source patches required.** See "Implementation notes" below for why, plus one useful bonus finding (`BGFX_PCI_ID_SOFTWARE_RASTERIZER`) and one mechanism you should explicitly avoid relying on (`Init::fallback`).

## Reconciling the apparent contradiction (issues #1974 / #1285 vs. the headless example)

There is no real contradiction once the issues are read in full (not just their titles) and dated against the current source:

- **#1974, "Does BGFX support headless mode?"** (opened Dec 2019, **closed**, 1 comment). Full body: *"We need a headless mode for automated testing, does BGFX support offscreen rendering without an output window/swap chain?"* Maintainer bkaradzic's only reply, in full: *"Depends on which renderer you use. One way to achieve headless for renderers that must have window is to create 1:1 window, and move it off the screen."* — this is the maintainer himself stating, six years ago, that headless support is **per-renderer**, and that only *some* renderers ("renderers that must have window") need the off-screen-dummy-window workaround. It does not single out Vulkan as one of the renderers needing the workaround, and predates the current `renderer_vk.cpp` headless branch by years.
- **#1285, "windowless offscreen rendering"** (opened Dec 2017, still **open**, labeled `enhancement`). Full body, verbatim: *"is there any way to use bgfx for offscreen/windowless rendering? I'm interested in running (**mainly OpenGL** in my case) applications on servers that don't always have the X system available."* — this issue is explicitly and exclusively about **OpenGL** on X-less Linux servers, never mentions Vulkan, and bkaradzic's reply openly says *"I never dealt with OpenGL"* on this topic. The subsequent community thread (dbacchet, adminradio, RicoP, PyryM — all read in full via the GitHub API, not summarized) discusses EGL (Linux) / CGL (macOS) as the real fix for windowless GL, bkaradzic rejecting the `RendererType::Noop` renderer as a non-answer ("They need GPU support without window. Noop provides no GPU support."), and PyryM's final comment noting Mesa llvmpipe + Xvfb as a practical workaround — i.e., this whole thread is the historical prehistory of exactly the GL-headless / software-rasterizer distinction this project's own prior research (`RENDER-BACKEND-DECISION.md`) already independently arrived at for the Vulkan-ICD-fallback design.
- **Neither issue reports the Vulkan backend failing or requiring a window.** They are old (2017/2019), general "does this exist at all" questions, and #1285 is scoped to OpenGL by its own original text. Both **predate** the current `renderer_vk.cpp` headless-extension-skipping logic and predate `examples/50-headless`, which — confirmed via the GitHub commits API — **was added on 2025-11-01** ("Added 50-headless example."), i.e. very recently, almost certainly as the formal resolution/demonstration of what #1974 asked for six years earlier. The prior research pass's flag ("open issues #1974, #1285 suggest disputed headless Vulkan support") should be read as **outdated** — it was a reasonable caution from search-snippet-level evidence, but primary-source reading resolves it: the issues are about the general/OpenGL case, not current Vulkan.

## Primary-source evidence: the headless example itself

`examples/50-headless/headless.cpp` (full file read directly, 253 lines) confirms the example matches (a) exactly:

```cpp
bgfx::Init init;
init.type     = args.m_type;      // renderer type comes from --gl/--vk/--d3d11/etc. CLI flag; never hardcoded
init.vendorId = args.m_pciId;
init.resolution.width  = 0;       // 0x0 signals "no backbuffer" (headless), not a real window's resolution
init.resolution.height = 0;

if (!bgfx::init(init) ) { /* ... */ }
```

- `init.platformData.nwh` is **never touched anywhere in the file** — it is left at its default-constructed value. `bgfx::PlatformData::nwh`'s own doc comment (`include/bgfx/bgfx.h:640-641`) states: *"Native window handle. If `NULL`, bgfx will create a headless context/device, **provided the rendering API supports it**."* — that trailing clause is precisely the per-renderer caveat this spike was asked to resolve, and (b) above answers it concretely.
- All actual rendering happens against a manually created `bgfx::FrameBufferHandle`/`bgfx::TextureHandle` (with `BGFX_TEXTURE_BLIT_DST|BGFX_TEXTURE_READ_BACK`), read back via `bgfx::readTexture()` and written to a `.tga` file — a real, non-trivial render (11x11 grid of rotating cubes across 5 frames), not a placeholder/no-op.
- The example does **not** branch on renderer type and carries no comment restricting it to a subset of backends — it is written to be renderer-agnostic via the CLI-selected `args.m_type`, consistent with (a): the headless *pattern itself* (0x0 resolution, untouched `nwh`) is common across backends; it is each backend's own internal init code (not the example) that determines whether that pattern actually produces a working context, which is exactly where the Windows-WGL exception in (b) lives.

## Critical Pitfalls (things that would trip up this integration if not caught)

### Pitfall 1: Trusting old GitHub issue titles/snippets over reading the actual current renderer source

**What goes wrong:** Search-snippet-level research (as the prior `RENDER-BACKEND-DECISION.md` pass did, reasonably, given its scope) flags #1974/#1285 as evidence the Vulkan backend has "rougher edges" around headless. Read in full and dated, neither issue is about Vulkan at all, and both predate the current headless code by years.

**Why it happens:** Issue titles ("windowless offscreen rendering") read as backend-agnostic; only the full body/comments reveal the OpenGL-specific scope.

**How to avoid:** For any bgfx capability claim tied to a specific renderer backend, read the actual `src/renderer_<backend>.cpp` for the `nwh`/`headless` handling directly — as done in this spike — rather than resting the conclusion on issue search results.

**Warning signs:** A claimed limitation with no line-numbered source citation, or one sourced only from an issue *title*.

**Phase to address:** Any phase that revisits or extends the render-backend decision (sgproc-render Phase 3, "Vulkan context setup" per `SUMMARY.md`, if bgfx is reconsidered there).

---

### Pitfall 2: Assuming "bgfx supports headless" is a single, backend-uniform guarantee

**What goes wrong:** `bgfx::PlatformData::nwh`'s own doc comment already warns "provided the rendering API supports it" — but it's easy to read the 50-headless example working once (with whatever `--type` was tested) and generalize that success to every backend, including the one the project will actually ship (Vulkan) and the ones it might additionally offer (OpenGL) without re-checking each backend's own code path.

**Why it happens:** bgfx presents one unified `bgfx::Init`/`bgfx::init()` API surface across all backends, so it looks backend-agnostic at the call-site even though headless support is implemented per-backend, independently, with genuinely different mechanisms (Vulkan: skip WSI extensions/swapchain; EGL: pbuffer surface; WGL: no headless path at all).

**How to avoid:** Verify headless support per backend actually used, at the source level, per platform actually targeted — not once, generically. This spike did that for Vulkan (all platforms it's enabled on) and OpenGL (Windows vs. Linux); it did **not** re-verify D3D11/D3D12/Metal headless behavior, since those are out of scope for this project's stated Vulkan/OpenGL/SwiftShader tiers.

**Warning signs:** A design doc that says "bgfx supports headless" without naming which backend(s) and which platform(s) that claim was checked against.

**Phase to address:** sgproc-render Phase 3 (Vulkan context setup) if/when bgfx is adopted — the headless-capability check belongs in that phase's own verification, not assumed from this document alone for any backend beyond Vulkan+OpenGL.

---

### Pitfall 3: Treating the SwiftShader/software-ICD tier as a distinct bgfx `RendererType`

**What goes wrong:** Designing the fallback chain as if bgfx needs to know about a separate "software Vulkan" renderer type, adding unnecessary bgfx-side branching or a fourth `RendererType` case that doesn't exist.

**Why it happens:** The three-tier mental model (Vulkan hw -> OpenGL -> SwiftShader) makes "SwiftShader" sound like a peer of "Vulkan" and "OpenGL," but from bgfx's perspective a software Vulkan ICD (SwiftShader or lavapipe) is selected entirely **underneath** `RendererType::Vulkan` by the platform's Vulkan loader/ICD enumeration (or forced via adapter selection) — it is the same bgfx renderer type as the hardware-GPU Vulkan tier, just resolving to a different device.

**How to avoid:** Both the "Vulkan hardware" and "Vulkan software-ICD" tiers should be implemented as two `bgfx::init()` attempts with `init.type = bgfx::RendererType::Vulkan` — the difference between them lives in `Init::vendorId`/adapter selection (or in which ICD the Vulkan loader resolves to), not in the bgfx renderer-type enum. Bonus finding: `bgfx::Init::vendorId` (`include/bgfx/bgfx.h:699-707`) has a literal named constant `BGFX_PCI_ID_SOFTWARE_RASTERIZER` documented as "Software rasterizer," which is likely the cleanest way to explicitly force the software tier on init rather than relying on ICD-registration-order tricks alone — worth a concrete spike of its own before committing to it as the mechanism, since this document did not trace how far that vendorId hint propagates into Vulkan physical-device selection.

**Warning signs:** Any design or code that special-cases "SwiftShader" as its own `bgfx::RendererType::*` value (no such value exists in current bgfx's `RendererType` enum).

**Phase to address:** Whichever phase implements the fallback-tier selection logic.

---

### Pitfall 4: Relying on bgfx's built-in `Init::fallback` to construct the three-tier chain automatically

**What goes wrong:** `bgfx::Init` has a real `fallback` bool (`include/bgfx/bgfx.h:713`, default `true`) that sounds like exactly what's needed — but it is not headless-aware, not software/hardware-aware, and its ordering is a hardcoded per-platform score table, not the app's desired tier order.

**Why it happens:** `rendererCreate()` (`src/bgfx.cpp:3220-3314`) scores every compiled-in, "supported" renderer by a fixed table (e.g. on Windows: D3D11 +20, D3D12 +10, nothing for OpenGL or Vulkan beyond the +1000 bonus if it's the explicitly-requested `init.type`) and cascades to the next-highest-scoring renderer **only when a `createFn()` call outright fails** (returns NULL) — not based on any headless/software-capability signal. On Windows specifically, per this table, a real fallback cascade would try D3D11/D3D12 before OpenGL (OpenGL scores 0 vs. Noop's +1 on that platform) — the opposite of what this project wants, since D3D isn't one of the three intended tiers at all.
`Init::fallback` also cannot distinguish "hardware Vulkan device failed, try software Vulkan ICD" from "hardware Vulkan device failed, try D3D11" — it has no concept of ICD-level software/hardware distinction, only renderer-type-level.

**How to avoid:** Set `init.fallback = false` and drive the three-tier sequence explicitly at the application level: attempt `bgfx::init()` with `type = Vulkan` (hardware) first; on failure, attempt `type = OpenGL` **only on platforms where it's genuinely headless-capable** (per Pitfall 2/finding (b) — i.e. skip this tier on Windows); on failure (or by design on Windows), attempt `type = Vulkan` again with the software-rasterizer vendor hint (Pitfall 3) as the final tier. This is a short, explicit sequence in application code — no bgfx patch required.

**Warning signs:** Any implementation that sets `bgfx::Init::fallback = true` (bgfx's default) and expects the resulting cascade to match the intended Vulkan -> OpenGL -> SwiftShader order.

**Phase to address:** Whichever phase implements the fallback-tier selection logic — this must be a documented, deliberate design decision, not the bgfx default.

---

### Pitfall 5: The Windows WGL "no-op" failure mode is silent, not a clean error

**What goes wrong:** On Windows, if `bgfx::init()` is called with `type = OpenGL` and `nwh == NULL` (no window, and no externally-supplied `platformData.context`), `GlContext::create()` (`src/glcontext_wgl.cpp:114-308`) does not fail loudly — it simply skips both context-creation branches (both gated on `nwh != NULL`), leaves `m_context == NULL`, and proceeds to `import()` (loading GL function pointers) and returns. Whether this surfaces as a clean `bgfx::init()` failure, a later crash on first draw call, or (worse) an apparent "success" with all subsequent GL calls silently no-op'ing depends on how `import()` and later draw-submission code handle a NULL context — this spike did not trace that far downstream, and it is exactly the kind of failure mode that could look like a working headless path in a quick smoke test on Windows and then fail unpredictably in production.

**Why it happens:** bgfx's own comment (line 122-127) frames `nwh == NULL` on WGL as "the assumption is that GL context was created by user (for example, using SDL, GLFW, etc.)" — i.e., it is documented as a supported *external-context* pattern, not a documented *failure* pattern, so it may not produce an obvious error at the point where the actual problem (no window, no external context) originates.

**How to avoid:** Do not rely on `bgfx::init()`'s return value alone to detect "OpenGL headless isn't supported here" on Windows — either skip the OpenGL tier on Windows entirely at the application level (the recommended mitigation, see Verdict (c)), or, if OpenGL-on-Windows is ever attempted, explicitly verify `bgfx::getRendererType() == RendererType::OpenGL` **and** exercise an actual draw-call-plus-readback round-trip (matching the 50-headless example's own approach) before trusting the tier is functional.

**Warning signs:** `bgfx::init()` returning `true` on Windows with `type = OpenGL` and no window/external context, but zero pixels or garbage data on readback.

**Phase to address:** The end-to-end verification phase (mirrors `SUMMARY.md`'s existing "Phase 6: End-to-end proof" pattern for the Vulkan-only design) — if the OpenGL tier is kept anywhere, it needs its own actual-pixel-readback test, not just an `init()` success check.

## Per-Platform / Per-Backend Matrix

| Platform | Vulkan headless (no `nwh`) | OpenGL headless (no `nwh`) | Notes |
|---|---|---|---|
| Linux | **Yes** — skips `VK_KHR_SURFACE`/`VK_KHR_SWAPCHAIN` extensions, no `VkSurfaceKHR` ever created (`renderer_vk.cpp`) | **Yes** — EGL pbuffer surface (`glcontext_egl.cpp`), no X/Wayland connection required | Both tiers genuinely headless on Linux; no platform-specific caveat needed here |
| Windows | **Yes** — same headless branch, no `nwh` needed | **No** — WGL path requires a real `nwh` or an externally-supplied GL context; no auto pbuffer/dummy-window fallback exists in bgfx's own WGL code | This is the one platform where the user's proposed mitigation (skip GL tier, use Vulkan/SwiftShader) is actually necessary and correct |
| macOS | **Yes** — via MoltenVK, same headless branch applies (Vulkan is enabled on `BX_PLATFORM_OSX` per `config.h`) | **N/A** — `BGFX_CONFIG_RENDERER_OPENGL` is not enabled on OSX by default in current bgfx (Metal/Vulkan only) | No OpenGL-headless question to answer here at all; it isn't a default backend |
| Android | **Yes** (Vulkan enabled on Android per `config.h`) | Not evaluated in this spike (project's stated tiers don't include mobile) | Out of scope for sgproc-render's server/node deployment target |

## "Looks Done But Isn't" Checklist

- [ ] **"bgfx supports headless" claim:** Often stated without naming which renderer backend and which platform — verify against the matrix above, not a blanket claim.
- [ ] **OpenGL tier on Windows:** `bgfx::init()` returning `true` is not sufficient evidence the tier works headless — verify with an actual draw-call + `readTexture()` round-trip producing non-garbage pixels (Pitfall 5).
- [ ] **SwiftShare/software tier "just works" via bgfx `fallback`:** Verify the tier sequence is explicitly application-driven (`fallback = false`, explicit `type`/`vendorId` per attempt), not relying on bgfx's built-in scored cascade (Pitfall 4).
- [ ] **`BGFX_PCI_ID_SOFTWARE_RASTERIZER` actually forces the software ICD:** This spike found the constant exists and is documented as "Software rasterizer," but did not trace its effect through Vulkan physical-device selection end-to-end — verify this experimentally before depending on it as the sole mechanism for the SwiftShader tier (Pitfall 3).

## Recommendation for the downstream architecture decision

This spike **confirms the technical premise the user raised is correct**: bgfx's Vulkan backend genuinely supports zero-window headless rendering on every platform it's enabled on (Linux, Windows, macOS-via-MoltenVK, Android), the window requirement that exists is real but isolated to the OpenGL backend, and even there it is platform-specific (Windows/WGL only — not Linux/EGL, and not applicable on macOS since OpenGL isn't a default macOS backend). The proposed mitigation — omit the OpenGL tier on Windows and rely on the Vulkan-hardware and Vulkan-software-ICD (SwiftShader) tiers there instead — is sound, requires no bgfx source modification, and is implementable as a short platform-conditional list in the application's own tier-selection logic (Pitfall 4's explicit-sequencing pattern), optionally reinforced by compile-time exclusion (`BGFX_CONFIG_RENDERER_OPENGL=0` on Windows builds) as a belt-and-suspenders measure.

This finding **does not by itself overturn** the prior `RENDER-BACKEND-DECISION.md`/`STACK.md` recommendation (hand-rolled Vulkan-only `RenderProcessor` + a software-Vulkan-ICD fallback, no engine) — that recommendation's core argument was that no engine (bgfx included) provides a genuine CPU/software rasterizer as an app-level "backend choice" the way MNN does for inference, which remains true: SwiftShare/lavapipe here is still a Vulkan-ICD-level fallback either way, with or without bgfx in the picture. What changes is narrower: the previously-flagged concern that "bgfx's Vulkan backend itself might not support genuine headless" is **resolved as unfounded** by this spike — if bgfx is adopted for other reasons (e.g. wanting OpenGL as a real secondary tier on Linux, or wanting bgfx's cross-backend shader/resource abstraction), its Vulkan headless support is not a blocker, and the OpenGL tier is usable on Linux but must be excluded on Windows.

## Sources

- Direct raw-file read: `bkaradzic/bgfx` `examples/50-headless/headless.cpp` (full 253-line file, fetched via `raw.githubusercontent.com` and read directly) — HIGH (primary source)
- Direct raw-file read: `bkaradzic/bgfx` `src/renderer_vk.cpp` (10,804 lines; specifically lines 1267, 1374-1378, 2038-2042, 7611-7649, 7752 and surrounding `nwh`/`headless`/`SwapChainVK` logic) — HIGH (primary source)
- Direct raw-file read: `bkaradzic/bgfx` `src/glcontext_wgl.cpp` (445 lines; specifically lines 114-329, `GlContext::create()`/`destroy()`) — HIGH (primary source)
- Direct raw-file read: `bkaradzic/bgfx` `src/glcontext_egl.cpp` (839 lines; specifically lines 153-179, 245-424, `SwapChainGL`/`GlContext::create()`) — HIGH (primary source)
- Direct raw-file read: `bkaradzic/bgfx` `src/config.h` (renderer-per-platform default-enable table, lines 20-120) — HIGH (primary source)
- Direct raw-file read: `bkaradzic/bgfx` `src/bgfx.cpp` (specifically `rendererCreate()`, lines 3220-3314, and `Init::Init()` defaults around line 4024-4030) — HIGH (primary source)
- Direct raw-file read: `bkaradzic/bgfx` `include/bgfx/bgfx.h` (specifically `PlatformData`, `Init`, `Resolution` struct definitions, lines 625-723) — HIGH (primary source)
- GitHub REST API direct fetch: `bkaradzic/bgfx` issue #1974 body + full comment thread (`api.github.com/repos/bkaradzic/bgfx/issues/1974` and `/comments`) — HIGH (primary source, not a search summary)
- GitHub REST API direct fetch: `bkaradzic/bgfx` issue #1285 body + full 6-comment thread (`api.github.com/repos/bkaradzic/bgfx/issues/1285` and `/comments`) — HIGH (primary source, not a search summary)
- GitHub REST API direct fetch: commit history for `examples/50-headless` (`api.github.com/repos/bkaradzic/bgfx/commits?path=examples/50-headless`), confirming the example was added 2025-11-01 — HIGH (primary source)
- Web search: initial discovery of the `50-headless` example's existence/directory number (confirmed and superseded by the direct commit-history/source reads above) — MEDIUM, used only as a pointer to the primary sources actually cited
- Prior session artifact: `.planning/workstreams/sgproc-render/research/RENDER-BACKEND-DECISION.md` — the document whose bgfx-headless-Vulkan concern this spike directly reconciles and updates — HIGH (primary source, this repo)

---
*Pitfalls/verification research for: bgfx zero-window headless rendering (Vulkan vs. OpenGL, per-platform), sgproc-render workstream*
*Researched: 2026-07-28*
