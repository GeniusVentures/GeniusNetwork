# Phase 1: bgfx & SwiftShader Vendoring - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-07-28
**Phase:** 1-bgfx-swiftshader-vendoring
**Areas discussed:** bgfx build integration, Build footprint, Submodule pinning strategy, Fate of the throwaway smoke-test target

---

## bgfx build integration

| Option | Description | Selected |
|--------|-------------|----------|
| Custom BUILD_COMMAND wrapper | ExternalProject_Add with a custom BUILD_COMMAND invoking bgfx's own GENie/bam toolchain, mirroring the existing MoltenVK precedent | (reversed, see below) |
| Adopt bgfx.cmake | Vendor the community `bgfx.cmake` wrapper as an additional submodule | ✓ (final) |
| You decide | Let research/planning pick | |

**User's original choice:** Custom `ExternalProject_Add`, following the Boost/OpenSSL per-platform pattern or the MoltenVK precedent — not `bgfx.cmake`.
**Notes:** User specifically flagged: if bgfx's build needs little/no per-platform customization, define per-platform vars in each platform's CMakeLists.txt and put the actual `ExternalProject_Add` in `CommonTargets.cmake` (the MNN pattern) rather than duplicating the whole block per platform (the Boost pattern). This determination was left for research/planning to make empirically.

**Revision (same day, post-session):** User reopened this decision, unfamiliar with GENie/bam and concerned they implied extra system dependencies; asked to switch to `bgfx.cmake` to avoid that. Claude clarified: GENie bootstraps from source and bgfx's own `Makefile` already wraps GENie+bam, so no extra system-level install was actually being introduced — the real trade-off is "wrap a second non-CMake build system inside `ExternalProject_Add`" (original plan) vs. "one more submodule, pure CMake" (`bgfx.cmake`). User confirmed they still prefer `bgfx.cmake` given that accurate framing. **Final decision: `bgfx.cmake`.** Follow-on question raised by the switch: whether bgfx.cmake is wired in via `ExternalProject_Add` (consistent with every other thirdparty dep) or `add_subdirectory()` (bgfx.cmake's own documented pattern) — left open for research.

**Second correction (same day):** User noted the repo moved from `widberg/bgfx.cmake` to **`bkaradzic/bgfx.cmake`** (per its own README) — bkaradzic is bgfx's own upstream author, which meaningfully reduces the "community fork could lag/get abandoned" risk originally flagged for this option. User also noted bgfx, bx, and bimg are already nested submodules *of* `bgfx.cmake` — so they don't need separate top-level `thirdparty/` submodule entries; only `bgfx.cmake` itself (recursively initialized) plus SwiftShader are new entries in `thirdparty/.gitmodules`. Both corrections applied to CONTEXT.md (D-01, D-02b, D-05/D-06, canonical refs, code context).

---

## Build footprint

| Option | Description | Selected |
|--------|-------------|----------|
| Restrict to Vulkan+GL | Compile bgfx with only Vulkan(+OpenGL on Linux) backends | ✓ |
| Leave bgfx defaults | Full default per-platform backend set (D3D/Metal/GL/Vulkan) | |
| You decide | Let research/planning pick | |

**User's choice:** Restrict to Vulkan+GL.
**Notes:** None.

| Option | Description | Selected |
|--------|-------------|----------|
| Vulkan ICD only | Build only SwiftShader's `vk_swiftshader` target | |
| Full SwiftShader build | Build entire SwiftShader repo including unused GL/D3D emulation | |
| You decide | Let research/planning pick | |

**User's choice (initial):** "As long as we maximize our CPU based rendering ability. If vulkan isn't usable but something else is, that would be a negative." — did not directly pick an option; raised a concern instead.
**Follow-up:** Claude clarified that the 3-tier architecture routes the CPU tier exclusively through SwiftShader's Vulkan ICD (never its GL/D3D emulation), so restricting the build to `vk_swiftshader` loses no capability this design ever exercises. Re-asked with that context.
**User's final choice:** Yes, Vulkan ICD only.

---

## Submodule pinning strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Pin to specific commit SHAs | Pin bgfx/bx/bimg/SwiftShader to tested commits | ✓ |
| Track upstream default branch | Point at master/main, updated on demand | |

**User's choice:** Pin to specific commit SHAs.
**Notes:** bgfx has no tagged releases at all, so a commit SHA is the only stable reference point regardless.

| Option | Description | Selected |
|--------|-------------|----------|
| Researcher picks latest known-good | gsd-phase-researcher selects and records the exact SHA | ✓ |
| I have specific commits/versions in mind | User specifies exact refs | |

**User's choice:** Researcher picks latest known-good.
**Notes:** No specific commits mandated.

---

## Fate of the throwaway smoke-test target

| Option | Description | Selected |
|--------|-------------|----------|
| Keep it permanently | Minimal CI build-health check, reusable by Phase 5's DETV-03 | ✓ |
| Delete after Phase 1 | Treat literally as throwaway per roadmap wording | |

**User's choice:** Keep it permanently.
**Notes:** None.

---

## Claude's Discretion

- Exact directory/target naming and location for the smoke-test target.
- Whether bx/bimg are vendored as separate submodules or nested some other way, informed by the actual bgfx commit chosen.
- Exact `BGFX_CONFIG_RENDERER_*` define set to restrict compiled backends.

## Deferred Ideas

None raised — discussion stayed within phase scope. Backend compile-scope questions that touch runtime tier *selection* (e.g. `BGFX_PCI_ID_SOFTWARE_RASTERIZER` forcing behavior) belong to Phase 3 and were not discussed here.
