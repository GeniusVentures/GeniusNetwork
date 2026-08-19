---
phase: 17-render-path-cross-hardware-tolerance
plan: 01
subsystem: render-processing
tags: [vulkan, glsl, phong-lighting, capture-harness, sgprocessingmanager]

requires:
  - phase: 14-configurable-normalization-precision
    provides: ResolveByteQuantMode/QuantizeByteBuffer schema-configurable tolerance mechanism, already wired at the render call site
  - phase: 10-capture-harness-diff-tool-quantization-stub
    provides: capture_harness CLI for local/cross-machine end-to-end fixture verification
provides:
  - "render-lighting fixture (JSON job + vertex/fragment GLSL + raw vertex data) exercising real per-fragment Phong math (pow/normalize/reflect)"
  - "Empirical proof the fixture builds+renders end-to-end via capture_harness on real Vulkan hardware"
  - "Corrected ROADMAP.md/REQUIREMENTS.md Phase 17 wording (three fixtures, not one; MSAA excluded per D-03)"
affects: [17-02-blending-fixture, 17-03-texturing-fixture, 17-05-cross-machine-capture, 17-06-tolerance-derivation]

tech-stack:
  added: []
  patterns: ["Phong lighting via push-constant vec3 uniforms (no RenderProcessor/schema change)", "Full-screen-triangle NDC trick for maximal fragment coverage with 3 vertices"]

key-files:
  created:
    - SuperGenius/test/src/processing_dispatch/lighting_vertex_shader.glsl
    - SuperGenius/test/src/processing_dispatch/lighting_fragment_shader.glsl
    - SuperGenius/test/src/processing_dispatch/lighting-vertex-data.raw
    - SuperGenius/test/src/processing_dispatch/lighting-fixture-definition.json
  modified:
    - .planning/workstreams/sgproc-render/ROADMAP.md
    - .planning/workstreams/sgproc-render/REQUIREMENTS.md

key-decisions:
  - "capture_harness requires --model-input-source for render-type fixtures that have no MNN model field; the plan's suggested invocation omitted it -- auto-fixed (Rule 3) by passing --model-input-source input:lightingVertexInput, mirroring the happy-path fixture's own input-name convention"

requirements-completed: [RENDTOL-01, RENDTOL-02]

coverage:
  - id: D1
    description: "Lighting fixture (JSON job + 2 GLSL shaders + raw vertex data) exercising real per-fragment Phong math with no RenderProcessor/schema changes"
    requirement: RENDTOL-01
    verification:
      - kind: other
        ref: "grep-verified acceptance criteria: valid JSON, no parameters/byteQuantMode key, pow(/normalize(/reflect( present in fragment shader, 72-byte vertex data, 6 scalar vertex_layout inputs"
        status: pass
    human_judgment: false
  - id: D2
    description: "Fixture builds and runs end-to-end through ProcessingManager::Create()+Process() on real Vulkan hardware via capture_harness, producing a non-error result"
    requirement: RENDTOL-01
    verification:
      - kind: e2e
        ref: "capture_harness.exe --fixture-root SuperGenius/test/src --fixture processing_dispatch/lighting-fixture-definition.json --label smoke-lighting --repeat 2 --model-input-source input:lightingVertexInput -- exit 0, 'wrote ... 2/2 stable runs' on NVIDIA RTX 4070 Ti SUPER"
        status: pass
    human_judgment: false
  - id: D3
    description: "Fixture declares no byteQuantMode/parameters, so ResolveByteQuantMode's N=0 identity fallback applies for Wave 4's raw-divergence capture"
    requirement: RENDTOL-02
    verification:
      - kind: other
        ref: "grep -c parameters/byteQuantMode over lighting-fixture-definition.json returns 0 matches"
        status: pass
    human_judgment: false
  - id: D4
    description: "ROADMAP.md/REQUIREMENTS.md Phase 17 wording corrected from singular 'a fixture' to the real three-fixture (texturing/blending/lighting) scope"
    verification:
      - kind: other
        ref: "scoped Edit calls to ROADMAP.md Phase 17 list bullet/Goal/SC1-2 and REQUIREMENTS.md RENDTOL-01/02 rows"
        status: pass
    human_judgment: false

duration: 25min
completed: 2026-08-19
status: complete
---

# Phase 17 Plan 1: Lighting Render Fixture Summary

**Phong-lit full-screen-triangle render fixture (GLSL pow/normalize/reflect, literal vec3 push-constant uniforms, zero RenderProcessor/schema changes) proven end-to-end via a local capture_harness run on real Vulkan hardware.**

## Performance

- **Duration:** 25 min
- **Started:** 2026-08-19T20:25:19Z (per STATE.md session start)
- **Completed:** 2026-08-19T20:32:29Z (final capture_harness verification run)
- **Tasks:** 2
- **Files modified:** 6 (4 created in SuperGenius submodule, 2 doc corrections in outer repo)

## Accomplishments
- Authored `render-lighting` fixture: a 3-vertex full-screen-triangle draw (the standard oversized-triangle NDC trick) whose fragment shader runs real per-fragment Phong lighting math (`pow`, `normalize`, `reflect`) against literal `vec3` uniforms (`lightDir`/`lightColor`/`viewPos`) — using only vertex/uniform mechanisms `RenderProcessor` already fully supports, with zero C++ or schema changes (D-05 lighting scope).
- Empirically proved the fixture compiles, links, and renders on real Vulkan hardware: `capture_harness` ran it 2/2 stable repeat iterations on an NVIDIA RTX 4070 Ti SUPER, exiting 0 with its own "wrote ... bytes" success message.
- Corrected ROADMAP.md's Phase 17 Goal/Success-Criteria wording and REQUIREMENTS.md's RENDTOL-01/02 rows from stale singular "a fixture" phrasing to the actual three-separate-fixture scope (texturing, blending, lighting; MSAA excluded per D-03's architectural hard-block on `VK_SAMPLE_COUNT_1_BIT`).
- Deliberately declared no `parameters`/`byteQuantMode` on the fixture, preserving `ResolveByteQuantMode`'s documented N=0 identity fallback so Wave 4's round-1 cross-machine capture measures genuine raw divergence (D-06 methodology step 1).

## Task Commits

Each task was committed atomically (submodule-first, then outer-repo pointer bump, per this project's convention):

1. **Task 1: Author the lighting fixture's shaders, vertex data, and job JSON**
   - `362f767c` (SuperGenius submodule, feat) — 4 new files: `lighting_vertex_shader.glsl`, `lighting_fragment_shader.glsl`, `lighting-vertex-data.raw`, `lighting-fixture-definition.json`
   - `e20856c` (outer repo, chore) — bump SuperGenius submodule pointer to `362f767c`
2. **Task 2: Smoke-verify the fixture via capture_harness and correct ROADMAP/REQUIREMENTS wording**
   - `e87e13f` (outer repo, docs) — ROADMAP.md/REQUIREMENTS.md wording corrections + smoke capture evidence files (2 `.cap` files under `phases/17-.../captures/smoke/`)

**Plan metadata:** committed via the standard `docs({phase}-{plan}): complete [plan-name] plan` final commit (see below)

_Note: no TDD tasks in this plan (fixture authoring + local verification only, per the plan's own read_first note mirroring 14-03-PLAN.md's fixture-only precedent)._

## Files Created/Modified
- `SuperGenius/test/src/processing_dispatch/lighting_vertex_shader.glsl` - GLSL vertex stage, 6 scalar inputs (`inPosX`/`inPosY`/`inPosZ`/`inNormX`/`inNormY`/`inNormZ`), reconstructs `pos`/`normal` vec3 locally, outputs `outNormal`/`outFragPos` varyings
- `SuperGenius/test/src/processing_dispatch/lighting_fragment_shader.glsl` - GLSL fragment stage, Phong lighting via a `Lighting` push-constant block (`lightDir`/`lightColor`/`viewPos`), `pow(...,32.0)` specular term
- `SuperGenius/test/src/processing_dispatch/lighting-vertex-data.raw` - 72-byte raw float32 vertex buffer: 3 vertices, 6 components each (pos xyz + constant normal (0,0,1)), full-screen-triangle NDC coordinates
- `SuperGenius/test/src/processing_dispatch/lighting-fixture-definition.json` - `render-lighting` job: 64x64 render target, `triangle_list` topology, literal `vec3` uniforms, no `parameters`/`byteQuantMode`
- `.planning/workstreams/sgproc-render/ROADMAP.md` - Phase 17 phase-list bullet, Goal line, and Success Criteria 1-2 pluralized from "a fixture" to the real three-fixture scope
- `.planning/workstreams/sgproc-render/REQUIREMENTS.md` - RENDTOL-01/02 rows pluralized to match

## Decisions Made
- **[Rule 3 - Blocking] `capture_harness` needs `--model-input-source` for render-type fixtures with no MNN `model` field.** The plan's suggested invocation (`--fixture-root ... --fixture ... --label ... --repeat 2 --output-dir ...`) failed with `capture_harness: fixture's pass has no model -- pass --model-input-source (e.g. input:renderInput)`. Read `capture_harness.cpp:426-448` to confirm this is a genuine CLI requirement for any fixture whose single pass lacks a `model` node (true of every render pass, since `model` is an MNN-only concept) — not specific to this fixture. Fixed by adding `--model-input-source input:lightingVertexInput`, mirroring the happy-path fixture's own documented `input:renderInput` convention. Both the smoke run and the plan's literal verification command (relabeled `smoke-lighting-verify`) then passed with exit 0 and the expected "wrote" substring.
- Chose the full-screen-triangle NDC trick (3 vertices covering the entire 64x64 target) with a constant normal so all 4096 fragments run the `pow`/`normalize`/`reflect` chain, per the plan's explicit design rationale (transcendental-function evaluation, not spatial normal variation, drives cross-hardware divergence).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Added missing `--model-input-source` flag to `capture_harness` invocation**
- **Found during:** Task 2 (smoke-verify via capture_harness)
- **Issue:** The plan's literal `capture_harness` command omitted `--model-input-source`, which is required whenever a fixture's render pass has no `model` field (true for this and every other render fixture) — the tool exits 1 with an explicit error rather than silently defaulting.
- **Fix:** Added `--model-input-source input:lightingVertexInput` to both the smoke run and the plan's verification command, matching the fixture's own vertex-input name and the happy-path fixture's established `input:renderInput` convention.
- **Files modified:** None (command-line invocation only, no source/fixture change)
- **Verification:** Both runs exited 0 with `capture_harness: wrote ... (72657 bytes, 2/2 stable runs, 0 chunk hashes self-checked)`.
- **Committed in:** e87e13f (Task 2 commit — the two resulting `.cap` files are the commit evidence)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** No scope creep — a CLI invocation correction only, no source files touched. The underlying fixture design was unaffected.

## Issues Encountered
None beyond the capture_harness flag documented above.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- The `render-lighting` fixture is real, builds, and renders correctly on this machine's Vulkan device — ready for Wave 4's cross-machine capture (17-05) once the blending (17-02) and texturing (17-03/17-04) fixtures also land.
- ROADMAP.md/REQUIREMENTS.md now accurately describe the three-fixture scope, so subsequent plans in this phase won't need to repeat this wording correction.
- This plan's smoke run only exercised one machine (Windows/`Mofu`); the Mac-mini leg of Phase 11's two-machine dataset is out of scope for this plan and belongs to Wave 4 (17-05).

---
*Phase: 17-render-path-cross-hardware-tolerance*
*Completed: 2026-08-19*

## Self-Check: PASSED

All 4 created artifact files exist on disk, the SUMMARY.md file exists, and all 3 commit hashes (362f767c in SuperGenius, e20856c and e87e13f in the outer repo) are present in git history.
