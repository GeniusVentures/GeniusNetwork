# Architecture Research: Cross-Hardware Deterministic Hashing (Quantization + Capture Harness)

**Domain:** Cross-hardware hash tolerance for SGProcessingManager job outputs (render + MNN inference pipelines)
**Researched:** 2026-08-07
**Confidence:** HIGH — every claim below is a direct source read with file:line citations against the current `SGProcessingManager` tree (post-Phase-09/v2.0). No external/web sources were needed; this is entirely a codebase-structure question.

**Relationship to v1.0 architecture research:** `.planning/workstreams/sgproc-render/research/ARCHITECTURE.md`'s prior content (Vulkan context creation, `RenderProcessor`'s pipeline-build/dispatch integration, PassType-vs-DataType enum collision, GLSL→SPIR-V compilation, coexistence-risk analysis) is **superseded by this milestone's scope** and not reproduced here — that pipeline is now built and shipped (v1.0 + v2.0 Phase 09). This document covers **only** what changed since: the artifact/manifest system (Phase 08, `ARTF-*`) and execution-context callback plumbing (Phase 07, `EXEC-*`) that this milestone's quantization/capture work must integrate with. Where useful, this doc references the shipped v1.0 render pipeline by file:line rather than re-describing it.

## Correction to the Milestone's Own Framing (read this first)

The milestone brief describes "ONE generic hashing call site: `sgns::sgprocmanagersha::sha256()` in `ProcessingManager.cpp` (around lines 1460-1509)." **This is not accurate for the hash that actually matters for cross-node comparison**, and the roadmap should be built around the corrected picture:

- `ProcessingManager.cpp:1460-1509` is real, but it computes the **model identity hash** (SHA-256 of the model/shader file bytes) and drives `ComputeArtifactIdentity()`/`ComputeManifestHash()` — these are **Phase 08 artifact/manifest bookkeeping**, added *after* a processor has already finished and already hashed its own output.
- The hash that is actually checked cross-node — `SGProcessing::SubTaskResult::chunk_hashes()`, consumed by `ProcessingValidationCore::ValidateResults`/`CheckSubTaskResultHashes` (`SuperGenius/src/processing/processing_validation_core.cpp:53-125,173-198`) — is populated from the `chunkhashes` vector that **each individual processor fills in during `StartProcessing()`**, long before `ProcessingManager.cpp`'s artifact code runs.
- There are in fact **~27 independent `sgns::sgprocmanagersha::sha256(...)` call sites**, not one:
  - 13 MNN processor files (`processing_processor_mnn_*.cpp`) × 2 calls each (one per-chunk, one combined) = 26
  - 1 in `processing_processor_render.cpp:2156` (single combined hash, no chunking)
  - Plus the Phase 08 bookkeeping calls in `ProcessingManager.cpp` (model identity), `artifact_types.hpp:78` (`ComputeArtifactIdentity`), and `artifact_serializer.hpp:63` (`ComputeManifestHash`) — these hash *already-produced* output bytes and are downstream of, not upstream of, the hashes that matter.

This matters directly for where quantization goes: **quantizing only at the `ProcessingManager.cpp` artifact-building layer would not touch the `chunkhashes` values that `ProcessingValidationCore` actually compares.** Quantization has to happen inside each processor, before its own hash calls — see Pattern 2.

## Standard Architecture

### System Overview (three hashing layers, annotated with the quantization insertion points this milestone adds)

```
┌────────────────────────────────────────────────────────────────────────────────┐
│  ProcessingManager::Process() / ProcessInternal()                              │
│  (SGProcessingManager/src/processingbase/ProcessingManager.cpp)                │
│                                                                                  │
│  m_processor->StartProcessing(chunkhashes, proc, imageData, modelFile,         │
│                                 parameters, execCtx)          [cpp:1304-1309]   │
└──────────────────────────────────┬───────────────────────────────────────────┘
                                    │
        ┌───────────────────────────┴────────────────────────────┐
        │                                                          │
┌───────▼─────────────────────────────┐          ┌────────────────▼──────────────────┐
│ MNN_* family (13 classes)            │          │ RenderProcessor (1 class)          │
│ processing_processor_mnn_*.cpp       │          │ processing_processor_render.cpp    │
│                                       │          │                                     │
│ ALL 13 types call                    │          │ readback is ALWAYS raw uint8        │
│ procresults->host<float>() for the   │          │ RGBA8/RGB8 bytes (ToVkFormat() only  │
│ output tensor — regardless of the    │          │ ever returns VK_FORMAT_R8G8B8A8_UNORM│
│ processor's own DataType label       │          │ or VK_FORMAT_R8G8B8_UNORM,           │
│ (INT/BOOL/BUFFER/IMAGE/etc.) — the   │          │ render.cpp:1052-1056). No chunking.  │
│ DataType label affects *input*       │          │                                     │
│ interpretation, not the hashed       │          │  ★ NEW quantization insertion:      │
│ output representation.               │          │    Readback() output, before        │
│                                       │          │    render.cpp:2156                  │
│  ★ NEW quantization insertion #1:    │          │    (byte/bit-level rounding —        │
│    per-chunk `data`/`dataSize`       │          │    tolerate ±1-2 LSB vendor          │
│    (float*), before the per-chunk    │          │    rasterizer/UNORM8-conversion      │
│    sha256 call inside the chunk loop │          │    rounding differences)             │
│    (float rounding — same function   │          │                                     │
│    for all 13 types)                 │          │  chunkhashes param explicitly        │
│                                       │          │  ignored: render.cpp:1992            │
│  ★ NEW quantization insertion #2     │          │  `(void)chunkhashes;` — single        │
│    (STITCHED family only, 6 of 13    │          │  combined hash only.                 │
│    types — see Pattern 1b): the      │          │                                     │
│    `stitchedOutput` accumulator,     │          │                                     │
│    before the combined sha256 call   │          │                                     │
└──────────────────┬────────────────────┘          └────────────────┬────────────────────┘
                    │                                                 │
                    └──────────────────┬──────────────────────────────┘
                                        │
                    chunkhashes (Layer A — cross-node-authoritative)
                    processResult.hash / result.hash (Layer B — combined per-subtask hash)
                    processResult.output_buffers (raw bytes, quantized, flow onward unchanged)
                                        │
┌───────────────────────────────────────▼──────────────────────────────────────────┐
│ ProcessingManager.cpp — ProcessOutput / Artifact / ExecutionManifest builder     │
│ (cpp:1360-1511) — Phase 08, ARTF-01..06                                          │
│                                                                                    │
│ ComputeArtifactIdentity(art, bufferData[outIdx], ...)   [cpp:1426-1428]          │
│   → hashes the SAME bytes the processor already quantized — automatically       │
│     consistent, ZERO additional change needed here (Layer C, non-authoritative  │
│     for cross-node comparison, but benefits "for free")                          │
│                                                                                    │
│ AddChunkHash(art, ch) for ch in chunkhashes  [cpp:1430-1437]                     │
│   → COPIES Layer A's already-quantized chunk hashes; not a new hash computation  │
└───────────────────────────────────────┬──────────────────────────────────────────┘
                                         │
                    FileManager::SaveASync(...) — UNCHANGED, cpp:1513-1817
```

### Component Responsibilities

| Component | Responsibility | File(s) |
|-----------|----------------|---------|
| `MNN_*` family (13 classes) | Own the ONLY point in the codebase where MNN's `float*` output tensor is materialized; each already computes 2 SHA-256 calls per pass today | `src/processors/processing_processor_mnn_*.cpp` |
| `RenderProcessor` | Owns the ONLY point where the Vulkan readback buffer (uint8 RGBA8/RGB8) is materialized; computes 1 SHA-256 call | `src/processors/processing_processor_render.cpp:2126-2160` |
| `ExecutionContext` | Already-established callback-injection bundle (cancel token, progress callback, budgets), threaded into every `StartProcessing()` call | `include/execution/execution_context.hpp:122-146` |
| `ProcessingManager` | Builds `ProcessOutput` (Artifacts + ExecutionManifest) from already-hashed processor output; does NOT see typed/raw values, only opaque `std::vector<char>` buffers + string metadata it derives itself from schema, not from the processor | `src/processingbase/ProcessingManager.cpp:1360-1511` |
| `Artifact` / `artifact_types.hpp` | Post-hoc metadata + hash record (dataType/format/dims/contentHash/chunkHashes strings); metadata is populated from `procInput.get_type()`/`get_format()` (schema-declared), not inspected at runtime from the actual buffer — confirms metadata-driven runtime dispatch is not how type identity flows in this codebase | `include/artifacts/artifact_types.hpp` |
| `artifact_serializer.{hpp,cpp}` | Deterministic fixed-layout binary serialization of `Artifact`/`ExecutionManifest` (`ARTIFACT_SERIALIZED_SIZE = 33880` bytes, `MANIFEST_SERIALIZED_SIZE = 5649` bytes) — **directly reusable as the capture file's metadata+hash record format** | `include/artifacts/artifact_serializer.hpp`, `src/artifacts/artifact_serializer.cpp` |
| `sgprocmanagersha` | Existing standalone CMake library wrapping OpenSSL SHA-256; the pattern to clone for a new quantization library | `src/util/CMakeLists.txt:14-26`, `include/util/sha256.hpp` |
| `ProcessingValidationCore` | The actual cross-node consumer of chunk hashes — `chunk_hashes()` comparison, currently has the known concatenation bug (out of scope this milestone, see PROJECT.md deferred) | `SuperGenius/src/processing/processing_validation_core.cpp` |

## Recommended Project Structure

```
SGProcessingManager/
├── include/util/
│   └── quantization.hpp            # NEW — sibling to sha256.hpp, same namespace style
├── src/util/
│   ├── quantization.cpp            # NEW — sibling to sha256.cpp
│   └── CMakeLists.txt              # + add_library(sgprocmanagerquant ...), mirrors
│                                    #   sgprocmanagersha's block exactly (lines 14-26)
├── src/processors/
│   ├── CMakeLists.txt              # + link sgprocmanagerquant (alongside existing
│   │                                #   sgprocmanagersha link at line 76)
│   ├── processing_processor_mnn_*.cpp   # MODIFIED (13 files) — 1 or 2 new lines each,
│   │                                #   immediately before each file's existing sha256 call(s)
│   └── processing_processor_render.cpp  # MODIFIED — 1 new line before render.cpp:2156
├── include/execution/
│   └── execution_context.hpp       # MODIFIED — + one new optional callback field
│                                    #   (raw pre-hash bytes hook), reusing the existing
│                                    #   progressCallback/cancelToken injection pattern
├── tools/capture/                  # NEW — standalone CLI tools, NOT under test/,
│   │                                #   NOT CTest-gated (see Pattern 5)
│   ├── CMakeLists.txt              # NEW — 2 add_executable() targets, no add_test()
│   ├── capture_harness.cpp         # NEW — runs a job, writes a capture file
│   ├── capture_diff.cpp            # NEW — reads 2 capture files, reports divergence
│   └── capture_file_format.hpp     # NEW — shared record struct: reuses
│                                    #   SerializeArtifact()/SerializeManifest() for the
│                                    #   metadata+hash portion, appends raw pre-/post-
│                                    #   quantization bytes (the one thing not persisted
│                                    #   anywhere today)
└── test/capture/                   # NEW, separate from tools/ — a THIN CTest smoke test
    ├── CMakeLists.txt              # NEW — 1 add_executable() + add_test(), GTest-based,
    │                                #   mirrors test/capability/CMakeLists.txt's convention
    └── capture_smoke_test.cpp      # NEW — asserts the harness runs and produces a
                                     #   well-formed file; does NOT assert cross-machine
                                     #   hash equality (that's the manual workflow)
```

### Structure Rationale

- **`tools/capture/` is a new top-level directory, not `test/capture/` alone**, because the capture harness and diff tool are not test *assertions* — a capture run always "succeeds" if it writes a well-formed file; there is no pass/fail condition until a human (or a later script) compares two files from two machines. Naming it `tools/` signals "manual/operator workflow" distinctly from the existing GTest/CTest conformance suite under `test/` (Phase 09's `TEST-01..10`), which is deliberately structured for one-shot automated pass/fail per plan.
- **A thin smoke test still lives under `test/capture/`**, following the existing hardware-tier convention already established by `processing_dispatch_test` (`SuperGenius/test/src/processing_dispatch/CMakeLists.txt`) and the Phase 09 conformance suites — this catches "the harness doesn't build" or "the harness crashes on this CI runner's GPU" without trying to make CTest responsible for a job that inherently needs 2+ different physical machines to be meaningful.
- **`quantization.hpp`/`.cpp` mirrors `sha256.hpp`/`.cpp` exactly** (same directory, same namespacing convention `sgns::sgprocmanager<name>`, same standalone CMake library pattern) because it is used from the exact same ~14 call sites, with the same "small utility library linked by every processor" shape sha256 already has.
- **`execution_context.hpp` gets ONE new field, not a new parameter threaded through `StartProcessing()`'s signature** — `StartProcessing()`'s 6-argument signature is a stable, already-`= 0`-versioned virtual interface implemented identically by 14 classes; adding a 7th positional parameter would require touching all 14 overrides for a capture-only feature. `ExecutionContext` is already the designated "extra stuff a processor might want, wired in without touching the pure-virtual signature" extension point (this is exactly why `progressCallback`/`cancelToken`/budgets live there instead of as `StartProcessing()` parameters).

## Architectural Patterns

### Pattern 1: Quantization is bimodal (2 strategies), not per-DataType (13 strategies) or metadata-dispatched

**What:** There are exactly two families of raw output representation in this codebase, not thirteen:

1. **MNN family (13 classes, all of them):** every single MNN processor's output tensor is read via `procresults->host<float>()` (confirmed by direct grep across all 13 files — `processing_processor_mnn_int.cpp:238`, `_bool.cpp:300`, `_buffer.cpp:231`, `_image.cpp:103`, `_string.cpp:127`, `_texture1d.cpp:372`, `_tensor.cpp:323`, `_texturecube.cpp:143,473,507`, `_volume.cpp:403`, `_mat2.cpp:300`, `_mat3.cpp:335`, `_mat4.cpp:335`, `_float.cpp:272`). The processor's declared `DataType` (INT/BOOL/BUFFER/IMAGE/STRING/TEXTURE1_D/TENSOR/TEXTURE_CUBE/VOLUME/MAT2/MAT3/MAT4/FLOAT) governs how the *input* is interpreted and how the artifact's metadata string is labeled after the fact — it has **no bearing on the hashed output's binary representation**, which is always raw IEEE-754 float32. One quantization function (float rounding) covers all 13 types.
2. **Render (1 class):** the readback buffer is always raw `uint8_t` RGBA8 or RGB8 (`ToVkFormat()` only ever returns `VK_FORMAT_R8G8B8A8_UNORM` or `VK_FORMAT_R8G8B8_UNORM`, `render.cpp:1052-1056` — no floating-point color-attachment format is reachable from the current schema/code). One quantization function (integer byte/bit rounding) covers this single type.

**Why metadata-driven (`artifact_types.hpp`'s `dataType`/`format` strings) dispatch is the wrong hook, even though it's tempting:** that metadata is populated in `ProcessingManager.cpp:1383-1412` **after** `StartProcessing()` has already returned and already hashed its output (both the per-chunk hash and the combined hash). Dispatching quantization there would be too late for the one hash that's actually cross-node-authoritative (`chunkhashes`, feeding `SubTaskResult::chunk_hashes`). The correct dispatch signal is simply **"which processor class is executing"** — a compile-time fact each `.cpp` file already knows about itself, not a runtime metadata lookup.

**Trade-off:** if a future milestone adds a floating-point render target format (e.g., HDR color attachments) or a genuinely non-float MNN output path, this bimodal split would need a third strategy — but nothing in the current schema/code reaches either case today, so building metadata-driven dispatch now would be speculative generality for a case that cannot currently occur.

### Pattern 1b: MNN's two combined-hash sub-families need different quantization insertion counts

**What:** Within the 13 MNN types, the **combined** (per-subtask) hash is built two different ways:

- **"Stitched" family (6 types: Float, Int, Mat2, Mat3, Mat4, Tensor):** accumulates a `stitchedOutput` float array via weighted averaging across overlapping patches (`_float.cpp:280-326`), then hashes `stitchedOutput`'s raw bytes directly (`_float.cpp:328-330`). This is a **different array with different values** than the per-chunk `data` pointer hashed earlier in the loop (`_float.cpp:307`) — averaging happens in between. **Requires 2 separate quantization insertion points**: once on `data` before the per-chunk hash, once on `stitchedOutput` before the combined hash.
- **"Chained" family (7 types: Bool, Buffer, Image, String, Texture1D, TextureCube, Volume):** the combined hash is a **rolling hash-of-hashes** — `combinedHash = previous_subTaskResultHash_bytes + current_chunk_hash_hex; subTaskResultHash = sha256(combinedHash)` (`_image.cpp:105-110`, same pattern in the other 6). **Requires only 1 quantization insertion point** — quantizing the per-chunk `data` before its own hash call automatically makes the chained combined hash deterministic too, since the combined hash is a pure function of already-quantized chunk hashes.

**Why this matters for build order/effort estimate:** it is not "13 types × 2 insertion points = 26 call sites needing independent logic." It is 1 shared quantization function, called at 13 (chunk) + 6 (stitched-combined) = 19 MNN insertion points, plus 1 render insertion point = **20 total insertion points**, all calling the same 2 small utility functions.

### Pattern 2: Quantize inside each processor, at (or immediately before) its existing hash call sites — not centrally in `ProcessingManager.cpp`

**What:** Insert `sgns::sgprocmanagerquant::QuantizeFloat(...)` (or the render equivalent) as the line immediately preceding each existing `sgprocmanagersha::sha256(...)` call already identified in Pattern 1/1b, mutating a **local copy** of the float buffer (not the MNN-owned tensor memory returned by `host<float>()`, which is `const float*` and may be reused/aliased internally by MNN — copy-then-quantize-then-hash, never mutate MNN's tensor buffer in place).

**Why here and not centrally:**
1. It is the only point in the whole call graph where both the raw values AND their true type (float vs. uint8-RGBA) are simultaneously and unambiguously known — see Pattern 1.
2. It automatically fixes all three hashing layers with a single change per insertion point: Layer A (`chunkhashes`, cross-node-authoritative) is fixed directly; Layer B (`subTaskResultHash`/`result.hash`) is fixed either directly (stitched family, render) or transitively (chained family, Pattern 1b); Layer C (`Artifact.contentHash`/`ComputeArtifactIdentity`, `ProcessingManager.cpp:1426-1428`) is fixed **for free**, because `output_buffers` (the bytes Layer C hashes) is built from the *same already-quantized* `stitchedOutput`/`readbackBytes` array (confirmed: `_float.cpp:353-362` copies `stitchedOutput` — the same array already hashed at line 330 — into `output_buffers`; `render.cpp:2157-2160` does the same with `readbackBytes`). No change is needed anywhere in `ProcessingManager.cpp`'s artifact-building code at all.
3. It keeps `ARTF-05`'s deterministic-serialization contract for `Artifact`/`ExecutionManifest` completely untouched — those structs' shapes and `SerializeArtifact`/`SerializeManifest` layouts don't change; only the bytes flowing *into* `ComputeArtifactIdentity` change, which was always going to vary run-to-run anyway (that's the entire point of ARTF-03's content-hash design).

**Trade-off:** this means the diff touches 14 processor `.cpp` files (13 MNN + 1 render) instead of 1 central file. This is the correct trade-off given the constraint that the cross-node-authoritative hash (`chunkhashes`) is produced inside those files and nowhere else — a "generic" central quantization step cannot reach it without restructuring `StartProcessing()`'s interface, which is out of scope and unnecessary.

### Pattern 3: One shared quantization utility library, N call-site invocations — not N bespoke implementations

**What:** `sgprocmanagerquant` (new library, mirrors `sgprocmanagersha`'s structure exactly) exposes two small free functions:

```cpp
// include/util/quantization.hpp
namespace sgns::sgprocmanagerquant
{
    /// Rounds each float32 value in-place to a fixed precision (decimal places or
    /// ULP-mask, exact strategy chosen empirically per the build-order note below).
    /// Used by all 13 MNN processor types — same function, same call signature,
    /// regardless of the processor's own DataType label.
    void QuantizeFloatBuffer( float *data, size_t count );

    /// Rounds/masks each uint8 channel value in-place to tolerate ±N LSB cross-vendor
    /// rasterizer rounding differences. Used only by RenderProcessor.
    void QuantizeByteBuffer( uint8_t *data, size_t count );
}
```

Each of the 20 insertion points from Pattern 1b becomes a 2-line change: copy the buffer if needed (MNN chunk case, since `host<float>()` returns `const float*`), call the appropriate function, hash the result — using the exact same call shape already present at every site today.

**When a per-processor bespoke implementation would have been justified (and isn't here):** if any MNN type's "float" output actually meant something semantically different per type (e.g., MNN_Bool's floats being 0.0/1.0 booleans where "rounding" should mean thresholding to exactly 0 or 1, not decimal-place rounding) such that one shared function couldn't serve all 13 correctly. This is worth flagging as a real, if narrow, risk: `MNN_Bool`'s output being literal booleans encoded as float 0.0/1.0 might already be "quantization-tolerant" by construction (no rounding needed, since the values are already exactly representable), while `MNN_Float`/`MNN_Tensor`'s outputs are genuine continuous values needing real rounding. **Recommendation:** keep one shared function, but verify empirically (via the capture harness, Pattern 4) whether any of the 13 types show near-zero cross-machine divergence already (meaning quantization is a no-op safety margin for that type) versus types that show real divergence (where the rounding precision actually matters) — this is exactly the kind of decision the empirical capture data should drive, not a priori per-type logic.

### Pattern 4: Capture file = existing `Artifact`/`ExecutionManifest` binary serialization + one new raw-bytes section

**What:** The capture file format should not be invented from scratch. `SerializeArtifact()`/`SerializeManifest()` (`artifact_serializer.hpp:39-64`) already produce a fixed-layout, deterministic binary blob (`ARTIFACT_SERIALIZED_SIZE = 33880` bytes, `MANIFEST_SERIALIZED_SIZE = 5649` bytes) containing exactly the metadata + hashes (`dataType`, `format`, `width`/`height`/`depth`, `byteSize`, `contentHash`, up to 1024 `chunkHashes`) that the diff tool needs to report "per-element divergence" context against. The capture harness's job is to call `ProcessingManager::Process()` (getting `ProcessOutput` — Artifacts + Manifest + `combinedHash` — for free, since `Process()` already returns this), then append one new section this milestone actually needs and which does **not exist anywhere today**: the raw pre-hash (and post-quantization) byte buffer itself.

**Why raw bytes don't exist anywhere today:** `ProcessOutput` (`ProcessingManager.hpp:46-60`) carries only `artifacts` (metadata+hashes, no raw bytes), `manifest`, and `combinedHash`. `ProcessingResult::output_buffers` (which *does* hold the raw bytes) is internal to `ProcessingManager::Process()`'s implementation and is never returned to `Process()`'s own caller. `FileManager::SaveASync` persists final bytes to IPFS/file storage (`ProcessingManager.cpp:1513-1817`), but that path is about distributed storage, not a structured, easily-diffable local capture record, and it doesn't run in the "job never gets scheduled through IPFS" manual-harness workflow this milestone needs.

**Recommended data-flow change:** add one new optional field to `ExecutionContext` (`execution_context.hpp:122-146`), following the exact same "no-op by default" pattern already established by `progressCallback`:

```cpp
// execution_context.hpp — NEW field, alongside progressCallback
std::function<void( const std::vector<uint8_t> &quantizedBytes,
                     const std::vector<uint8_t> &preQuantizeBytes )> rawOutputCapture;
```

Each of the 14 processor files invokes this callback (if set) at the same point it invokes `QuantizeFloatBuffer`/`QuantizeByteBuffer` — one extra `if (execCtx.rawOutputCapture) execCtx.rawOutputCapture(...)` line per insertion point. The capture harness constructs its own `ExecutionContext` and calls the existing 5-argument `Process(ioc, chunkhashes, model, output_locations, externalExecCtx)` overload (`ProcessingManager.hpp:105-109`) — which was **already built for exactly this purpose** ("Lets a caller cancel mid-execution... before calling" — the same override point generalizes cleanly to "lets a caller observe raw bytes"). No change to `ProcessOutput`'s shape, no change to `StartProcessing()`'s pure-virtual signature, no change to production callers (who never set `rawOutputCapture` and pay zero cost).

**Trade-off:** this does mean `ExecutionContext` (already documented as "bundles everything a processor needs for an execution") grows a capture-only concern. This is consistent with its existing role, but worth a one-line doc comment noting the field is capture/debug-oriented and expected to stay unset (nullptr) in production job execution — mirroring how `ExecutionContext::NoOp()` (`execution_context.hpp:139-145`) already documents the "test-only" no-op construction pattern.

### Pattern 5: Capture harness + diff tool are standalone CLI executables, outside CTest pass/fail — with a thin CTest smoke test alongside the existing conformance suite for regression coverage only

**What:** Two new `add_executable()` targets under `tools/capture/`, **not** registered via `add_test()`/CTest. `capture_harness` runs one job definition end-to-end (through `ProcessingManager::Process()`, as Pattern 4 describes) and writes a capture file. `capture_diff` takes two capture file paths and reports per-artifact/per-chunk divergence (byte-exact match / max delta / mantissa-bit differences, reusing `DeserializeArtifact()`/`DeserializeManifest()` to parse both files).

**Why not CTest-gated:** the entire point of this workflow is comparing output **across two different physical machines** (the user's Mac + PC, per the milestone's acceptance criterion) — CTest runs on one machine per invocation. There is no meaningful automated pass/fail CTest could assert *before* the empirical capture data exists to pick a quantization precision (see Build Order below); forcing this into CTest's single-run-per-machine model would either be a no-op (capture-only, nothing to assert) or would need artificial two-machine CI orchestration this milestone doesn't call for.

**Why still register a thin smoke test:** following the exact convention already established by `test/capability/CMakeLists.txt` (GTest executable + `add_test`) and Phase 09's hardware-tier conformance suites, add `test/capture/capture_smoke_test.cpp` that runs `capture_harness` once (or calls its internals directly) on the current CI machine and asserts only: the process exits 0, the output file is non-empty, and `DeserializeArtifact`/`DeserializeManifest` can round-trip it. This catches "the harness doesn't build" or "the harness crashes on this GPU" regressions in ordinary CI, without pretending to validate cross-machine hash equality.

## Data Flow

### Augmented Hashing + Capture Flow (this milestone's additions marked ★)

```
MNN_Float::StartProcessing() / RenderProcessor::StartProcessing()
    │
    ├─ (MNN, per patch in loop) data = procresults->host<float>()   [_float.cpp:272]
    │      ★ NEW: localCopy = copy(data); QuantizeFloatBuffer(localCopy, count)
    │      ★ NEW: if (execCtx.rawOutputCapture) capture(quantized=localCopy, raw=data)
    │      chunkhashes.push_back( sha256(localCopy, ...) )     [was: sha256(data,...), _float.cpp:307]
    │
    ├─ (MNN, stitched family only) stitchedOutput built via weighted average [_float.cpp:280-326]
    │      ★ NEW: QuantizeFloatBuffer(stitchedOutput.data(), stitchedOutput.size())
    │      ★ NEW: if (execCtx.rawOutputCapture) capture(...)
    │      subTaskResultHash = sha256(stitchedOutput bytes)     [was unquantized, _float.cpp:330]
    │      output_buffers built FROM stitchedOutput (now quantized, no extra work) [_float.cpp:353-362]
    │
    ├─ (Render) readbackBytes = Readback(...)                  [render.cpp:2126-2131]
    │      ★ NEW: QuantizeByteBuffer(readbackBytes.data(), readbackBytes.size())
    │      ★ NEW: if (execCtx.rawOutputCapture) capture(...)
    │      result.hash = sha256(readbackBytes)                  [was unquantized, render.cpp:2156]
    │      output_buffers built FROM readbackBytes (now quantized) [render.cpp:2157-2160]
    │
    ▼
ProcessingManager.cpp — ProcessOutput builder [cpp:1360-1511]
    │  ComputeArtifactIdentity(bufferData) — hashes already-quantized bytes, UNCHANGED code
    │  AddChunkHash(chunkhashes) — copies already-quantized Layer-A hashes, UNCHANGED code
    ▼
returns ProcessOutput { artifacts, manifest, combinedHash }
    │
    ├─────────────────────────────────────────────┐
    ▼                                              ▼
FileManager::SaveASync(...) — UNCHANGED    ★ NEW: capture_harness (tools/capture/)
(IPFS/file persistence, production path)      calls Process(ioc, chunkhashes, model,
                                               output_locations, externalExecCtx)
                                               with its own ExecutionContext whose
                                               rawOutputCapture is set; serializes
                                               ProcessOutput via existing
                                               SerializeArtifact/SerializeManifest +
                                               appends the captured raw/quantized bytes
                                               → writes ONE capture file
                                                    │
                                          (run again on a 2nd/3rd machine)
                                                    │
                                                    ▼
                                          ★ NEW: capture_diff (tools/capture/)
                                          reads 2 capture files, reports per-artifact
                                          max delta / mantissa-bit diff / hash match
```

### Key Data Flows

1. **Quantization flows automatically into all 3 hash layers from a single insertion point per array** (Pattern 2) — this is the load-bearing design decision. No separate "quantize for artifacts" step is ever needed.
2. **Raw bytes reach the capture harness via a new opt-in `ExecutionContext` callback, not via a new return-value field** (Pattern 4) — keeps `ProcessOutput`'s ARTF-05 deterministic-serialization contract untouched, and keeps zero cost for production callers who never set the callback.
3. **The capture file's metadata/hash section is not a new format** — it's the existing `SerializeArtifact`/`SerializeManifest` binary layout, with one new appended raw-bytes section per artifact.

## Anti-Patterns

### Anti-Pattern 1: Dispatching quantization strategy from `Artifact.dataType`/`format` strings in `ProcessingManager.cpp`

**What people would do:** since `artifact_types.hpp` already carries `dataType`/`format` char arrays, and the milestone question explicitly asks "should quantization be dtype-dispatched using the existing artifact-metadata type info" — it's tempting to add a `switch(artifact.dataType)` in `ProcessingManager.cpp`'s artifact-building loop (`cpp:1370-1440`) that calls a quantization function before `ComputeArtifactIdentity()`.
**Why it's wrong:** that metadata is populated *after* `StartProcessing()` already returned and already computed `chunkhashes` (Layer A) and `processResult.hash` (Layer B) — the two hashes that actually matter for cross-node comparison and for the milestone's own acceptance criterion ("same job run on ≥3 different machines... produces matching post-quantization hashes"). Quantizing only at this layer would leave the actually-compared hashes unquantized.
**Do this instead:** quantize inside each processor at its existing hash call sites (Pattern 2); metadata-string dispatch is unnecessary because the type is already known unambiguously by which of the 14 processor files is executing (Pattern 1).

### Anti-Pattern 2: Mutating the MNN tensor's `host<float>()` buffer in place

**What people would do:** call `QuantizeFloatBuffer(const_cast<float*>(data), count)` directly on the pointer returned by `procresults->host<float>()`, to avoid an extra copy.
**Why it's wrong:** that memory is owned by MNN's `Tensor`/session internals, not the calling processor code — mutating it in place risks corrupting values MNN itself may still read (e.g., during teardown, or if the same tensor backing store is reused across patches in the per-chunk loop), and violates the `const float*` contract the MNN API itself declares.
**Do this instead:** copy into a locally-owned `std::vector<float>`, quantize the copy, hash the copy. This is a small, bounded-size copy (one chunk's worth of floats) already happening implicitly at several of these call sites in spirit (e.g. `_float.cpp`'s `patch` vector), so the pattern is already idiomatic here.

### Anti-Pattern 3: Treating all 13 MNN types as needing 2 quantization insertion points each

**What people would do:** assume uniform structure across all 13 processor types and add "quantize before per-chunk hash" + "quantize before combined hash" everywhere, 26 insertion points.
**Why it's wrong:** 7 of the 13 types (the "chained" family, Pattern 1b) compute their combined hash as `sha256(previousHash + currentChunkHashHex)` — a hash-of-hashes with no independent float buffer to re-quantize. Adding a second quantization call there would be dead code (there's no second float array to quantize) or, worse, someone might mistakenly try to quantize the *hash bytes themselves*, which is meaningless.
**Do this instead:** quantize only where an actual float buffer exists before a hash call — 13 chunk-level insertions + 6 stitched-combined-level insertions (not 7) = 19 MNN insertions + 1 render insertion = 20 total (Pattern 1b).

### Anti-Pattern 4: Making the capture harness / diff tool GTest CTest assertions that gate CI

**What people would do:** wrap `capture_harness` in a GTest `TEST()` that asserts specific hash values, or wrap `capture_diff` in a test that fails CI if two captures from the *same* CI machine don't match.
**Why it's wrong:** same-machine determinism is already covered by the existing `DETV-01`/`DETV-02` requirements and their v1.0 tests (10/10 repeat-run bit-exact hash matching, per PROJECT.md's Phase 3 history) — that's a different, already-solved problem. This milestone's actual question (cross-*hardware* tolerance) cannot be validated by a single CI runner at all; asserting anything cross-machine-shaped from a single-machine CTest run would be a false signal.
**Do this instead:** the thin smoke test (Pattern 5) only asserts the harness runs and produces a well-formed file — the real validation is the manual multi-machine workflow the milestone describes, run by the user across their Mac + PC + a third machine.

### Anti-Pattern 5: Choosing a quantization precision before running the capture harness on real hardware

**What people would do:** pick a rounding precision (e.g. "round every float to 4 decimal places" or "mask the low 2 bits of every RGBA8 channel") upfront, based on intuition about typical float/GPU rounding error, then build the capture harness afterward just to confirm it worked.
**Why it's wrong:** the milestone explicitly defers "schema-configurable quantization precision" and wants a *fixed* precision chosen for real — but the actual cross-hardware divergence magnitude (mantissa bits differing between the user's Mac's Metal/MoltenVK backend and a PC's native Vulkan ICD, or between two different MNN CPU/Vulkan backend float rounding modes) is an empirical fact this codebase cannot predict from source alone. Guessing a precision risks either (a) too coarse — destroying legitimate output fidelity for no reason, or (b) too fine — not actually absorbing the real divergence, silently failing the milestone's own acceptance criterion.
**Do this instead:** ship the capture harness with quantization as a currently-identity/no-op-precision hook first (Build Order below), gather real Mac-vs-PC-vs-third-machine capture files, run `capture_diff` to see the actual observed max-delta/mantissa-bit-difference distribution, **then** pick the fixed precision from that data.

## Integration Points (file:line specificity)

| Integration point | File:line | New vs. Modified |
|---|---|---|
| Quantization library | `include/util/quantization.hpp`, `src/util/quantization.cpp` | **NEW** |
| Quantization library CMake target | `src/util/CMakeLists.txt` (append after line 26, mirror lines 14-26) | **MODIFIED** |
| Link quantization lib into processors | `src/processors/CMakeLists.txt:76` (alongside existing `sgprocmanagersha`) | **MODIFIED** |
| MNN per-chunk quantize+capture hook, 13 files | e.g. `processing_processor_mnn_float.cpp:306-307` (immediately before the existing chunk `sha256` call); same pattern at `_int.cpp:~272`, `_bool.cpp:~334`, `_buffer.cpp:~265`, `_image.cpp:104-105`, `_string.cpp:~142`, `_texture1d.cpp:~406`, `_tensor.cpp:~357`, `_texturecube.cpp:~475,~509`, `_volume.cpp:~516`, `_mat2.cpp:~334`, `_mat3.cpp:~334`, `_mat4.cpp:~334` | **MODIFIED** (13 files) |
| MNN stitched-combined quantize+capture hook, 6 files | `processing_processor_mnn_float.cpp:327-330` (immediately before `stitchedStr`/combined `sha256`); same pattern at `_int.cpp:~295`, `_mat2.cpp:~357`, `_mat3.cpp:~357`, `_mat4.cpp:~357`, `_tensor.cpp:~380` | **MODIFIED** (6 files) |
| Render quantize+capture hook | `processing_processor_render.cpp:2126-2156` (quantize `readbackBytes` right after `Readback()` returns, before line 2156's `sha256`) | **MODIFIED** |
| `ExecutionContext` new capture-callback field | `include/execution/execution_context.hpp:122-146` (add field alongside `progressCallback`) | **MODIFIED** |
| Capture harness entry point | `tools/capture/capture_harness.cpp` — calls `ProcessingManager::Process(ioc, chunkhashes, model, output_locations, externalExecCtx)` per `include/processingbase/ProcessingManager.hpp:105-109` | **NEW** |
| Diff tool entry point | `tools/capture/capture_diff.cpp` — uses `DeserializeArtifact`/`DeserializeManifest` per `include/artifacts/artifact_serializer.hpp:41-55` | **NEW** |
| Capture file format helper | `tools/capture/capture_file_format.hpp` — wraps `SerializeArtifact`/`SerializeManifest` (`artifact_serializer.hpp:39,45`) plus a new raw-bytes section | **NEW** |
| CTest smoke test | `test/capture/CMakeLists.txt`, `test/capture/capture_smoke_test.cpp` (mirrors `test/capability/CMakeLists.txt` convention) | **NEW** |
| Root test registration | `test/CMakeLists.txt:1-4` — add `add_subdirectory(capture)` | **MODIFIED** |
| Unaffected (confirm no change needed) | `include/processingbase/ProcessingManager.hpp:46-60` (`ProcessOutput`), `ProcessingManager.cpp:1360-1511` (Artifact/Manifest builder), `include/artifacts/artifact_types.hpp`, `include/artifacts/artifact_serializer.hpp` | **NONE** — confirmed these automatically benefit from quantized bytes with zero code changes (Pattern 2) |

## Build Order (accounts for: empirical data must come before precision is fixed)

1. **Capture harness first, with quantization as an identity/no-op stub.** Add the `ExecutionContext::rawOutputCapture` field and the 20 insertion points (Pattern 1b), but have `QuantizeFloatBuffer`/`QuantizeByteBuffer` do nothing yet (or round to a deliberately-obviously-wrong placeholder like 15 decimal places, effectively a no-op) — this validates all the plumbing (capture callback fires, capture file writes, `capture_diff` parses two files) without yet claiming a real answer.
2. **Build `capture_diff`** (reads 2 files, reports max delta / mantissa-bit-difference distribution / hash-match boolean) — needed immediately after step 1 to make the captured data legible at all.
3. **Run the harness on the user's Mac + PC + a third machine** (per the milestone's own acceptance criterion) on a small representative job set (at least one MNN pass, one render pass). Collect 3+ capture files per job.
4. **Diff pairwise, observe real divergence** — this produces the actual mantissa-bit/byte-delta distribution needed to pick a real, justified fixed precision (e.g., "floats diverge only in the last 2-3 decimal digits → round to 4 decimal places is safely conservative"; "RGBA8 channels diverge by at most ±1 → mask the low bit is sufficient").
5. **Implement the real quantization logic** in `QuantizeFloatBuffer`/`QuantizeByteBuffer` using the precision chosen from step 4's data.
6. **Re-run the harness + diff on all 3+ machines** to empirically confirm post-quantization hashes now match — this is the milestone's literal acceptance criterion and should be the last step, not assumed from source-level reasoning alone.
7. **Land the thin CTest smoke test** (Pattern 5) once the harness's shape is stable, so future refactors don't silently break the harness without at least one machine's CI noticing.

This order deliberately defers "what precision" as long as possible while still landing all the invasive, review-heavy plumbing (14 processor files + `ExecutionContext`) early, once, in a form that doesn't need to be revisited when the precision number changes later — only the two small function bodies in `quantization.cpp` change between step 1 and step 5.

## Scaling Considerations

Not applicable in the traditional sense — this is a per-job, per-process hashing pipeline running once per subtask, not a service under load. The only "scale" concern is: the capture file's raw-bytes section is O(output size) per artifact, uncapped (unlike `Artifact.chunkHashes[1024]`'s fixed cap) — for very large render targets or tensor outputs, the capture harness should stream to disk rather than buffer the full raw-bytes section in memory, but this is an implementation detail of `tools/capture/capture_harness.cpp`, not an architectural concern requiring a scaling table.

## Sources

Direct source reads (HIGH confidence, primary source, all file:line cited inline above):
- `SGProcessingManager/src/processingbase/ProcessingManager.cpp` (lines 1260-1817, plus `Process()`/`ProcessInternal()` declarations)
- `SGProcessingManager/include/processingbase/ProcessingManager.hpp` (full file)
- `SGProcessingManager/include/processors/processing_processor.hpp` (full file)
- `SGProcessingManager/include/execution/execution_context.hpp` (full file)
- `SGProcessingManager/include/artifacts/artifact_types.hpp` (full file)
- `SGProcessingManager/include/artifacts/artifact_serializer.hpp` (full file)
- `SGProcessingManager/include/util/sha256.hpp`, `src/util/sha256.cpp`, `src/util/CMakeLists.txt` (full files)
- All 13 `SGProcessingManager/src/processors/processing_processor_mnn_*.cpp` files (grepped for `sha256`/`host<`/`data`/`dataSize` call sites; `_float.cpp` and `_image.cpp` read in full detail as representative of the "stitched" and "chained" sub-families respectively)
- `SGProcessingManager/src/processors/processing_processor_render.cpp` (lines 350-370, 1040-1310, 2080-2168)
- `SuperGenius/src/processing/processing_validation_core.cpp` (full file) — confirms `chunkhashes`/`chunk_hashes()` is the actual cross-node-compared field
- `SGProcessingManager/test/CMakeLists.txt`, `test/capability/CMakeLists.txt`, `SuperGenius/test/src/processing_dispatch/CMakeLists.txt` — existing conformance-suite/CTest conventions
- `.planning/workstreams/sgproc-render/research/ARCHITECTURE.md` (v1.0 doc, read for established render-pipeline conventions, not re-researched here)
- `.planning/workstreams/sgproc-render/REQUIREMENTS.md`, `.planning/PROJECT.md` — milestone scope and history

---
*Architecture research for: sgproc-render workstream v2.1 (Cross-Hardware Hash Tolerance)*
*Researched: 2026-08-07*
