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
| Custom BUILD_COMMAND wrapper | ExternalProject_Add with a custom BUILD_COMMAND invoking bgfx's own GENie/bam toolchain, mirroring the existing MoltenVK precedent | ✓ |
| Adopt bgfx.cmake | Vendor the community `bgfx.cmake` wrapper as an additional submodule | |
| You decide | Let research/planning pick | |

**User's choice:** Custom `ExternalProject_Add`, following the Boost/OpenSSL per-platform pattern or the MoltenVK precedent — not `bgfx.cmake`.
**Notes:** User specifically flagged: if bgfx's build needs little/no per-platform customization, define per-platform vars in each platform's CMakeLists.txt and put the actual `ExternalProject_Add` in `CommonTargets.cmake` (the MNN pattern) rather than duplicating the whole block per platform (the Boost pattern). This determination was left for research/planning to make empirically.

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
