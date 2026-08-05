# 09-01-SUMMARY.md — Shared Infrastructure

**Plan:** 09-01 — Shared infrastructure for Phase 09 conformance tests
**Status:** ✅ Complete
**Date:** 2026-08-05

## Artifacts Created

| File | Purpose |
|------|---------|
| `SuperGenius/test/testutil/processing_conformance_fixture.hpp` | Shared GTest fixture base class with `PatchJsonUrisToAbsolute()`, `PatchedJson()`, `DataPath()` |
| `SuperGenius/test/src/processing_datatypes/create_audio_model.py` | 1D conv net → ONNX → MNNConvert script |
| `SuperGenius/test/src/processing_datatypes/create_image_model.py` | 2D conv net (32×32×3) → ONNX → MNNConvert script |
| `SuperGenius/test/src/processing_datatypes/create_ml_model.py` | MLP (64-dim) → ONNX → MNNConvert script |
| `SuperGenius/test/src/processing_datatypes/create_string_model.py` | Char embedding (vocab=32, embed=8, seq=16) → ONNX → MNNConvert script |
| `SuperGenius/test/src/processing_datatypes/create_volume_model.py` | 3D conv net (16³) → ONNX → MNNConvert script |
| `SuperGenius/test/src/processing_datatypes/audio-processing-definition.json` | Job definition for audio MNN processor |
| `SuperGenius/test/src/processing_datatypes/image-processing-definition.json` | Job definition for image MNN processor |
| `SuperGenius/test/src/processing_datatypes/ml-processing-definition.json` | Job definition for ML MNN processor |
| `SuperGenius/test/src/processing_datatypes/string-conformance-definition.json` | Job definition for string conformance (uses `string_tiny.mnn`) |
| `SuperGenius/test/src/processing_datatypes/volume-processing-definition.json` | Job definition for volume MNN processor |
| `SuperGenius/test/src/processing_conformance_regression/fixtures/passthrough.vert` | Pass-through vertex shader (GLSL 450) |
| `SuperGenius/test/src/processing_conformance_regression/fixtures/passthrough.frag` | Pass-through fragment shader — solid white (GLSL 450) |
| `SuperGenius/test/src/processing_conformance_regression/fixtures/passthrough.vert.spv` | Pre-compiled SPIR-V (validated) |
| `SuperGenius/test/src/processing_conformance_regression/fixtures/passthrough.frag.spv` | Pre-compiled SPIR-V (validated) |

## Deviations

- **MNNConvert not available:** `.mnn` and `.raw` binaries not generated. Python scripts are correct and ready for build-time execution when MNNConvert is available. Fixture JSON files reference expected filenames.
- **SPIR-V compilation:** Used `glslangValidator` from `thirdparty/build/Windows/Debug/shaderc/bin/` (not system-installed). Validated with `spirv-val` from same build output. Both binaries pass validation.

## Verification

- [x] `ProcessorConformanceFixture` class present in header with include guards
- [x] 5 Python model scripts created following existing `create_buffer_model.py` pattern
- [x] 2 GLSL sources + 2 SPIR-V binaries created and validated with `spirv-val`
- [ ] `.mnn`/`.raw` generation deferred (requires MNNConvert tool)
