---
phase: 17-render-path-cross-hardware-tolerance
plan: 03
subsystem: render-processing
tags: [vulkan, glsl, quicktype, schema, texturing, wire-format, sgprocessingmanager]

requires:
  - phase: 17-render-path-cross-hardware-tolerance
    provides: "Plan 01's lighting fixture and Plan 02's blending fixture -- both establish the wire-format-pairing discipline (RESEARCH.md Pitfall 2) this plan's larger texture-buffer extension follows"
  - phase: 02-schema-extension-shader-spir-v-validation-pipeline
    provides: "quicktype regeneration workflow, vertex_buffer/index_buffer's input:-prefix schema convention this plan mirrors for texture_buffer"
  - phase: 03-renderprocessor-implementation-determinism
    provides: "SerializeRenderPassConfig/ParseRenderPassConfig wire format, GetInputIndex/GetSubCidForProc input-fetch pattern, rejectUnsupportedBufferSourcePrefix gate"
provides:
  - "texture_buffer/texture_filter schema definitions (D-05 texturing scope), regenerated into sgns::TextureBuffer/TextureFilter and Pass::get_texture_buffer(), structurally mirroring vertex_buffer's input:-prefix convention (not DataType::TEXTURE2_D's MNN-chunking shape)"
  - "CheckProcessValidity()'s new fail-closed gate rejecting non-input:-prefixed texture_buffer.source"
  - "ProcessingManager::Process()'s new texture-fetch block (GetInputIndex/GetSubCidForProc) populating textureBuffer/textureWidth/textureHeight/hasTextureBuffer"
  - "SerializeRenderPassConfig()/ParseRenderPassConfig() paired wire-format edit for the new trailing texture section, closing RESEARCH.md Pitfall 2 in a single task/commit"
  - "texturing-source-image.raw (16384-byte synthetic 64x64 RGBA8 checkerboard) and a Create()-only GTest (RenderPassTextureBufferSourcePrefixGating) proving the input:/output: prefix gate without depending on Wave 3's not-yet-built sampler infrastructure"
affects: [17-04-texturing-vulkan-implementation, 17-05-cross-machine-capture, 17-06-tolerance-derivation]

tech-stack:
  added: []
  patterns: ["texture_buffer as an independent pass-level field (not routed through the uniforms map), mirroring vertex_buffer/index_buffer's existing bypass of ResolveUniforms/PackUniformValue (RESEARCH.md Pitfall 4)"]

key-files:
  created:
    - SuperGenius/SGProcessingManager/generated/TextureBuffer.hpp
    - SuperGenius/SGProcessingManager/generated/TextureFilter.hpp
    - SuperGenius/test/src/processing_dispatch/texturing-source-image.raw
  modified:
    - SuperGenius/SGProcessingManager/gnus-processing-schema.json
    - SuperGenius/SGProcessingManager/generated/Pass.hpp
    - SuperGenius/SGProcessingManager/generated/Generators.hpp
    - SuperGenius/SGProcessingManager/generated/SGNSProcMain.hpp
    - SuperGenius/SGProcessingManager/src/processingbase/ProcessingManager.cpp
    - SuperGenius/SGProcessingManager/src/processors/processing_processor_render.cpp
    - SuperGenius/SGProcessingManager/include/processors/processing_processor_render.hpp
    - SuperGenius/test/src/processing_dispatch/processing_dispatch_test.cpp
    - SuperGenius/test/src/processing_dispatch/CMakeLists.txt

key-decisions:
  - "No deviations from plan needed -- every file matched the plan's own read_first/action text and RESEARCH.md Pattern 3's proposed code verbatim; quicktype regeneration produced only the expected new/changed files (grep-verified: git status showed exactly TextureBuffer.hpp/TextureFilter.hpp new, Pass.hpp/Generators.hpp/SGNSProcMain.hpp changed, no unrelated drift like Plan 02's data_type/llm fix)"

requirements-completed: [RENDTOL-01, RENDTOL-02]

coverage:
  - id: D1
    description: "texture_buffer/texture_filter schema definitions added, regenerated (no hand-edits) into sgns::TextureFilter enum and TextureBuffer class with get_source/get_width/get_height/get_filter, plus Pass::get_texture_buffer(); render-type allOf's required list unchanged (texture_buffer stays optional)"
    requirement: RENDTOL-01
    verification:
      - kind: other
        ref: "grep-verified: generated/TextureFilter.hpp declares enum class TextureFilter : int { LINEAR, NEAREST }; generated/TextureBuffer.hpp declares get_source/get_width/get_height/get_filter; generated/Pass.hpp declares get_texture_buffer returning boost::optional<TextureBuffer>; required array at gnus-processing-schema.json:276 unchanged (3 elements, texture_buffer absent)"
        status: pass
    human_judgment: false
  - id: D2
    description: "CheckProcessValidity() gates texture_buffer.source through the existing rejectUnsupportedBufferSourcePrefix lambda (input:-only, optional field) -- proven by a Create()-only GTest accepting input: and rejecting output:"
    requirement: RENDTOL-01
    verification:
      - kind: unit
        ref: "SuperGenius/test/src/processing_dispatch/processing_dispatch_test.cpp#ProcessingDispatchTest.RenderPassTextureBufferSourcePrefixGating -- 2 ProcessingManager::Create() calls, 0 ->Process( calls, PASSED (189ms local run; 100% tests passed via full processing_dispatch_test suite, 12/12)"
        status: pass
    human_judgment: false
  - id: D3
    description: "SerializeRenderPassConfig()/ParseRenderPassConfig() both append/read the new trailing texture section (has_texture_buffer + width/height/texture_len/bytes) in the same order, in the same task/commit, closing RESEARCH.md Pitfall 2's wire-format-pairing risk for texturing's data path"
    requirement: RENDTOL-01
    verification:
      - kind: other
        ref: "grep -c 'textureBytes|textureWidth|textureHeight|hasTextureBuffer|outHasTextureBuffer|outTextureWidth|outTextureHeight|outTextureBytes' returns 19 on ProcessingManager.cpp and 25 on processing_processor_render.cpp (both >= 4 required); every new ParseRenderPassConfig read uses the existing bounds-checked ReadU32/ReadU8/ReadBytes + fail() pattern; ProcessingBase target builds cleanly"
        status: pass
    human_judgment: false
  - id: D4
    description: "texturing-source-image.raw exists as a deterministic 64x64 RGBA8 8x8-tiled checkerboard (16384 bytes), registered in processing_dispatch_test's POST_BUILD fixture-copy list"
    requirement: RENDTOL-01
    verification:
      - kind: other
        ref: "wc -c texturing-source-image.raw returns 16384; file committed alongside the CMakeLists.txt copy_if_different entry"
        status: pass
    human_judgment: false
  - id: D5
    description: "The render path's byte-quantization tolerance mechanism (ResolveByteQuantMode/QuantizeByteBuffer, Phase 14) remains unmodified -- this plan is schema/wire-format/validation scope only, no tolerance derivation (deferred to Wave 4/6, 17-05/17-06)"
    requirement: RENDTOL-02
    verification:
      - kind: other
        ref: "grep-verified: no changes to quantization.hpp/quantization.cpp/ResolveByteQuantMode call sites in this plan's diff"
        status: pass
    human_judgment: false

duration: 27min
completed: 2026-08-19
status: complete
---

# Phase 17 Plan 3: Texturing Schema and Wire-Format Contract Summary

**texture_buffer/texture_filter schema definitions (input:-prefix convention mirroring vertex_buffer, explicitly not DataType::TEXTURE2_D's MNN-chunking shape), CheckProcessValidity's fail-closed gate, ProcessingManager::Process()'s texture-fetch block, and the paired SerializeRenderPassConfig/ParseRenderPassConfig wire-format extension -- the "define contracts" half of texturing's Interface-First split, proven end-to-end by a Create()-only counter-test and a 16384-byte synthetic checkerboard fixture, with zero dependency on Wave 3's not-yet-built Vulkan sampler infrastructure.**

## Performance

- **Duration:** 27 min
- **Started:** 2026-08-19T22:20:00Z
- **Completed:** 2026-08-19T22:47:41Z
- **Tasks:** 3
- **Files modified:** 12 (7 in SGProcessingManager nested submodule, 3 test/fixture files in SuperGenius, plus submodule pointer bumps)

## Accomplishments
- Added named top-level schema definitions `texture_filter` (`nearest`/`linear`) and `texture_buffer` (`source`/`width`/`height`/`filter`, `input:`-prefix pattern, `width`/`height` bounded to 8192 as a DoS guard) to `gnus-processing-schema.json`; wired `pass.texture_buffer` as an optional field (never added to the render-type `allOf`'s required list) — regenerated via quicktype with zero hand-edits, producing `sgns::TextureFilter` (enum `LINEAR`/`NEAREST`), `sgns::TextureBuffer` (plain `get_source`/`get_width`/`get_height`, optional `get_filter`), and `Pass::get_texture_buffer()`.
- Extended `CheckProcessValidity()`'s existing `PassType::RENDER` gate with a `texture_buffer` check reusing the exact same `rejectUnsupportedBufferSourcePrefix` lambda `vertex_buffer`/`index_buffer` already call — `texture_buffer` itself stays optional (no "must be present" check), only "if present, must be `input:`-prefixed."
- Added a texture-fetch block to `Process()`'s `isRender` branch (`GetInputIndex`/`GetSubCidForProc`, mirroring `vertexBuffer`'s own fetch shape and defense-in-depth prefix re-check) and paired `SerializeRenderPassConfig()`'s new trailing append (`has_texture_buffer` + conditional `width`/`height`/`texture_len`/bytes) with `ParseRenderPassConfig()`'s exact bounds-checked inverse read, in the same task/commit, closing RESEARCH.md's Pitfall 2 for texturing's data path. `StartProcessing()`'s call site now declares and threads the four new locals through — captured but not yet consumed (Wave 3's Plan 17-04 is the intended consumer).
- Generated a deterministic 64x64 RGBA8 8x8-tiled checkerboard (`texturing-source-image.raw`, 16384 bytes, opaque red/cyan) via a one-off Python script (not committed, per the project's raw-fixture-without-generator convention), registered it in `processing_dispatch_test`'s POST_BUILD fixture-copy list, and added `RenderPassTextureBufferSourcePrefixGating` — a `Create()`-only GTest with two inline job JSON variants (`input:`/`output:`-prefixed `texture_buffer.source`) proving the prefix gate without ever calling `Process()` (Wave 3's sampler code doesn't exist yet).

## Task Commits

Each task was committed atomically (submodule-first, then outer-repo pointer bump, per this project's convention):

1. **Task 1: Add texture_buffer/texture_filter schema definitions and CheckProcessValidity's fail-closed gate**
   - `0e7a2f7` (SGProcessingManager nested submodule, feat) — schema definitions, regenerated headers (TextureBuffer.hpp, TextureFilter.hpp, Pass.hpp, Generators.hpp, SGNSProcMain.hpp), CheckProcessValidity gate
   - `91d3dc54` (SuperGenius submodule, chore) — bump SGProcessingManager submodule pointer to `0e7a2f7`
   - `6145bfc` (outer repo, chore) — bump SuperGenius submodule pointer to `91d3dc54`
2. **Task 2: Fetch texture bytes in Process() and pair the wire-format edit across Serialize/Parse**
   - `bddc595` (SGProcessingManager nested submodule, feat) — Process()'s texture-fetch block, SerializeRenderPassConfig/ParseRenderPassConfig paired trailing texture section (both .hpp and .cpp), StartProcessing()'s new locals
   - `5ce9160c` (SuperGenius submodule, chore) — bump SGProcessingManager submodule pointer to `bddc595`
   - `9517a43` (outer repo, chore) — bump SuperGenius submodule pointer to `5ce9160c`
3. **Task 3: Generate the synthetic texture asset and prove the prefix gate with a Create()-only test**
   - `55f8dc03` (SuperGenius submodule, feat) — texturing-source-image.raw, CMakeLists.txt fixture-copy entry, RenderPassTextureBufferSourcePrefixGating test
   - `9015b77` (outer repo, chore) — bump SuperGenius submodule pointer to `55f8dc03`

**Plan metadata:** committed via the standard `docs({phase}-{plan}): complete [plan-name] plan` final commit (see below)

_Note: no TDD tasks in this plan (schema/wire-format/test authoring, mirroring 17-01's and 17-02's fixture-only precedent)._

## Files Created/Modified
- `SuperGenius/SGProcessingManager/gnus-processing-schema.json` - `texture_filter`/`texture_buffer` named top-level definitions added; `pass.texture_buffer` added alongside `vertex_buffer`/`index_buffer`; render-type `required` list left unchanged
- `SuperGenius/SGProcessingManager/generated/TextureBuffer.hpp` (new) - quicktype-regenerated `sgns::TextureBuffer` class (`get_source`/`get_width`/`get_height`/`get_filter`)
- `SuperGenius/SGProcessingManager/generated/TextureFilter.hpp` (new) - quicktype-regenerated `enum class TextureFilter : int { LINEAR, NEAREST }`
- `SuperGenius/SGProcessingManager/generated/Pass.hpp` - regenerated to add `get_texture_buffer()`/`set_texture_buffer()`
- `SuperGenius/SGProcessingManager/generated/Generators.hpp`, `generated/SGNSProcMain.hpp` - regenerated to reference the new `TextureBuffer.hpp` include and JSON (de)serialization for `pass.texture_buffer`
- `SuperGenius/SGProcessingManager/src/processingbase/ProcessingManager.cpp` - `CheckProcessValidity()`'s new `texture_buffer` gate; `Process()`'s new texture-fetch block; `SerializeRenderPassConfig()`'s 4 new trailing parameters + append block; doc comment updated
- `SuperGenius/SGProcessingManager/src/processors/processing_processor_render.cpp` - `ParseRenderPassConfig()`'s 4 new trailing out-parameters + bounds-checked inverse read; `StartProcessing()`'s new locals threaded through the call
- `SuperGenius/SGProcessingManager/include/processors/processing_processor_render.hpp` - `ParseRenderPassConfig()` declaration updated identically; doc comment extended
- `SuperGenius/test/src/processing_dispatch/texturing-source-image.raw` (new) - 16384-byte synthetic 64x64 RGBA8 8x8-tiled checkerboard (opaque red/cyan)
- `SuperGenius/test/src/processing_dispatch/CMakeLists.txt` - added `texturing-source-image.raw` to the POST_BUILD fixture-copy list
- `SuperGenius/test/src/processing_dispatch/processing_dispatch_test.cpp` - new `TEST_F(ProcessingDispatchTest, RenderPassTextureBufferSourcePrefixGating)`

## Decisions Made
- No deviations from plan needed — every file matched the plan's own `read_first`/`action` text and RESEARCH.md Pattern 3's proposed code verbatim. quicktype regeneration produced exactly the expected file set (`TextureBuffer.hpp`/`TextureFilter.hpp` new; `Pass.hpp`/`Generators.hpp`/`SGNSProcMain.hpp` changed) with no unrelated drift, unlike Plan 02's incidental `data_type`/`"llm"` schema-drift discovery.
- Generated `texturing-source-image.raw` via a one-off Python script (not committed), matching the project's existing convention of committing raw binary fixture assets without their generator tooling (e.g. `happy-path-vertex-data.raw` has no committed generator).
- Confirmed the plan's literal `ctest -R RenderPassTextureBufferSourcePrefixGating` verify command doesn't match this project's ctest test-naming convention (ctest registers one test per binary target — `processing_dispatch_test`, not per-GTest-case) — verified the new test directly via `--gtest_filter=*RenderPassTextureBufferSourcePrefixGating*` (PASSED) and via the full `ctest -R processing_dispatch_test` run (12/12 tests passed, 100%), which is the actually-meaningful verification for this project's test infrastructure.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- `texture_buffer`'s schema/validation/wire-format contract is complete and independently testable via `Create()` alone — ready for Wave 3's Plan 17-04 to implement the actual Vulkan sampler/descriptor/upload consumption against `ParseRenderPassConfig()`'s new `outHasTextureBuffer`/`outTextureWidth`/`outTextureHeight`/`outTextureBytes` out-parameters (`BuildPipeline()`'s new descriptor binding, `UploadBuffers()`'s new image upload).
- This plan intentionally does not implement any GPU-side texture sampling — `hasTextureBuffer`/`textureWidth`/`textureHeight`/`textureBytes` are captured and threaded through `StartProcessing()`'s local scope but never consumed by `BuildPipeline`/`UploadBuffers`/the fragment shader in this plan. That consumption is explicitly Wave 3's (17-04's) scope, per D-05's Interface-First split.
- `T-17-06`'s byte-count-matches-dimensions validation (`textureBytes.size() == width * height * 4`) remains 17-04's responsibility (documented in the plan's own threat model) — not implemented here, since only the GPU-binding consumer knows the expected bytes-per-pixel for the format it will bind.
- REQUIREMENTS.md's RENDTOL-01/RENDTOL-02 checkboxes should NOT be marked fully "Complete" after this plan — this is 3/8 plans into an 8-plan phase; texturing's Vulkan implementation (17-04) and all cross-machine tolerance derivation (Waves 4-7, 17-05/17-06) remain pending. Per STATE.md's existing note (added after Plan 17-02), this discrepancy is flagged for correction at phase 17 close/verification, not resolved by this plan.

---
*Phase: 17-render-path-cross-hardware-tolerance*
*Completed: 2026-08-19*

## Self-Check: PASSED

All 3 created artifact files exist on disk (TextureBuffer.hpp, TextureFilter.hpp, texturing-source-image.raw), the SUMMARY.md file exists, and all 8 task commit hashes (0e7a2f7, bddc595 in SGProcessingManager; 91d3dc54, 5ce9160c, 55f8dc03 in SuperGenius; 6145bfc, 9517a43, 9015b77 in the outer repo) are present in their respective git histories.
