# Phase 10: Capture Harness & Diff Tool (Quantization Stub) - Pattern Map

**Mapped:** 2026-08-10
**Files analyzed:** 12 (new + modified)
**Analogs found:** 12 / 12 (all have strong in-repo analogs; research already located exact insertion lines)

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `SGProcessingManager/include/util/quantization.hpp` | utility | transform | `SGProcessingManager/include/util/sha256.hpp` | exact |
| `SGProcessingManager/src/util/quantization.cpp` | utility | transform | `SGProcessingManager/src/util/sha256.cpp` | exact |
| `SGProcessingManager/src/util/CMakeLists.txt` (modified) | config | build | same file, `sgprocmanagersha` block (lines 14-26) | exact |
| `SGProcessingManager/src/processors/CMakeLists.txt` (modified) | config | build | same file, existing `sgprocmanagersha` link line ~76 | exact |
| `SGProcessingManager/include/execution/execution_context.hpp` (modified) | model/config-struct | event-driven (callback injection) | same file, `progressCallback` field + `ExecutionContext::NoOp()` | exact |
| `SGProcessingManager/src/processors/processing_processor_mnn_float.cpp` (modified, representative of 13 MNN files) | processor | streaming/transform | itself (pattern repeats identically across all 13 MNN files) | exact |
| `SGProcessingManager/src/processors/processing_processor_render.cpp` (modified) | processor | streaming/transform | itself (single combined-hash call site) | exact |
| `SGProcessingManager/include/artifacts/artifact_serializer.hpp` / `.cpp` (modified — new raw-bytes section) | serializer | file-I/O (binary) | same file, `SerializeArtifact`/`SerializeManifest` | exact |
| `SGProcessingManager/tools/capture/capture_file_format.hpp` | utility/serializer | file-I/O (binary) | `artifact_serializer.hpp` (wraps it) | role-match |
| `SGProcessingManager/tools/capture/capture_harness.cpp` | CLI entry point (like a controller) | request-response / batch (drives a job once, or N times with `--repeat`) | `ProcessingManager::Process()` caller pattern used in `test/capability` and dispatch tests; no existing standalone CLI tool exists, so this is a role-match, not exact | role-match |
| `SGProcessingManager/tools/capture/capture_diff.cpp` | CLI entry point | batch/transform (reads 2 files, computes diff stats) | none in-repo (first diff-style CLI); nearest role-match is `capture_harness.cpp` itself (sibling file, shares CLI arg-parsing/file-I/O idioms) | no analog |
| `SGProcessingManager/tools/capture/CMakeLists.txt` | config | build | `SGProcessingManager/src/util/CMakeLists.txt` (library target pattern) + `test/capability/CMakeLists.txt` (executable target pattern, minus `add_test`) | role-match |
| `SGProcessingManager/test/capture/CMakeLists.txt` + `capture_smoke_test.cpp` | test | request-response (smoke) | `SGProcessingManager/test/capability/CMakeLists.txt` + `SuperGenius/test/src/processing_dispatch/CMakeLists.txt` | exact |

## Pattern Assignments

### `SGProcessingManager/include/util/quantization.hpp` + `src/util/quantization.cpp` (utility, transform)

**Analog:** `SGProcessingManager/include/util/sha256.hpp` (full file, 14 lines) + sibling `.cpp`/CMake target `sgprocmanagersha`.

**Full header to mirror** (`include/util/sha256.hpp:1-13`):
```cpp
#ifndef SGPROCMGR_SHA256_HPP
#define SGPROCMGR_SHA256_HPP

#include <string_view>
#include <vector>
#include <gsl/span>

namespace sgns::sgprocmanagersha
{
  std::vector<uint8_t> sha256(const void* data, size_t dataSize);
}

#endif
```

**Pattern to copy for the new header** — same include-guard style (`SGPROCMGR_<NAME>_HPP`), same namespace convention `sgns::sgprocmanager<name>`, same "free function taking raw pointer + size" signature shape. Research's exact recommended signatures (already vetted against all 14 call sites):
```cpp
namespace sgns::sgprocmanagerquant
{
    void QuantizeFloatBuffer( float *data, size_t count );   // MNN family — no-op/identity in Phase 10
    void QuantizeByteBuffer( uint8_t *data, size_t count );  // Render — no-op/identity in Phase 10
}
```
Phase 10 requirement: both bodies are literal no-ops (or documented identity pass-through) — do NOT implement real rounding yet (that is Phase 12, per the hard dependency chain in ROADMAP.md).

**CMake target to mirror** (`src/util/CMakeLists.txt:14-26`):
```cmake
add_library(sgprocmanagersha
    sha256.cpp
	../../include/util/sha256.hpp
)
target_include_directories(sgprocmanagersha PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/../../include>
	$<BUILD_INTERFACE:${OPENSSL_INCLUDE_DIR}>
)
target_link_libraries(sgprocmanagersha
    PRIVATE
    OpenSSL::Crypto
)
sgnus_install(sgprocmanagersha)
```
New `sgprocmanagerquant` target: same shape, minus the `OPENSSL_INCLUDE_DIR`/`OpenSSL::Crypto` lines (quantization has no OpenSSL dependency) — just a plain library with no third-party deps, still call `sgnus_install(sgprocmanagerquant)` at the end to match the existing install-everything convention in this file.

---

### `SGProcessingManager/include/execution/execution_context.hpp` (modified — new field)

**Analog:** the file's own existing `progressCallback` field + `ExecutionContext::NoOp()` factory (lines 122-146, read in full).

**Struct to extend** (lines 122-146):
```cpp
struct ExecutionContext
{
    ExecutionContext() = default;
    ExecutionContext( const ExecutionContext & )            = delete;
    ExecutionContext &operator=( const ExecutionContext & ) = delete;
    ExecutionContext( ExecutionContext && )                 = delete;
    ExecutionContext &operator=( ExecutionContext && )      = delete;

    CancellationToken                     cancelToken;
    std::function<void( ProgressEvent )>   progressCallback;
    uint64_t                              deadlineMs            = 0;
    uint64_t                              gpuMemoryBudget       = 0;
    uint64_t                              maxOutputArtifactBytes = 0;

    static std::unique_ptr<ExecutionContext> NoOp()
    {
        auto ctx = std::make_unique<ExecutionContext>();
        ctx->cancelToken.SetCallback( []() {} );
        ctx->progressCallback = []( const ProgressEvent & ) {};
        return ctx;
    }
};
```

**Pattern to copy:** add one new field alongside `progressCallback`, same `std::function<...>` shape, defaulting to unset (`nullptr`), and extend `NoOp()` to leave it unset (do NOT auto-assign a lambda in `NoOp()` — unlike `progressCallback`, this one must stay opt-in so production/no-op callers pay zero cost, per research Pattern 4). Recommended field per research (SUMMARY/ARCHITECTURE Pattern 4):
```cpp
/// Capture-only hook: fires with (quantized bytes, pre-quantize bytes) at each
/// processor's existing hash call site. Unset (nullptr) in production job execution;
/// only tools/capture/capture_harness.cpp sets this. Mirrors progressCallback's
/// opt-in, no-op-by-default injection pattern.
std::function<void( const std::vector<uint8_t> &quantizedBytes,
                     const std::vector<uint8_t> &preQuantizeBytes )> rawOutputCapture;
```
Add a one-line doc comment (as shown) — matches the existing per-field doc-comment convention in this struct (`///< ...` trailing comments on every other field).

---

### 13 MNN processor files (modified), representative: `processing_processor_mnn_float.cpp` (processor, streaming/transform)

**Analog:** itself — every one of the 13 MNN files follows this exact shape; `_float.cpp` was read in full as the "stitched family" representative.

**Per-chunk quantize+capture hook** — insert immediately before the existing per-chunk hash call (`_float.cpp:272-308`):
```cpp
const float *data = procresults->host<float>();   // existing line, ~272
// ... existing per-chunk loop body building stitchedOutput ...
auto hash = sgprocmanagersha::sha256( data, dataSize );      // existing line, 307 — DO NOT mutate data in place (const float*, MNN-owned)
chunkhashes.emplace_back( hash.begin(), hash.end() );          // existing line, 308
```
**New insertion (2 lines, before line 307):**
```cpp
std::vector<float> localCopy( data, data + ( dataSize / sizeof( float ) ) );
sgns::sgprocmanagerquant::QuantizeFloatBuffer( localCopy.data(), localCopy.size() );
if ( execCtx.rawOutputCapture )
{
    // pack localCopy/data into uint8_t vectors and invoke callback
}
auto hash = sgprocmanagersha::sha256( localCopy.data(), localCopy.size() * sizeof(float) ); // was: sha256(data, dataSize)
```

**Stitched-combined quantize+capture hook** (6 of 13 types only: Float, Int, Mat2, Mat3, Mat4, Tensor) — insert immediately before the combined hash (`_float.cpp:328-330`):
```cpp
std::string stitchedStr( reinterpret_cast<const char *>( stitchedOutput.data() ),  // existing line 328
                          stitchedOutput.size() * sizeof( float ) );               // existing line 329
subTaskResultHash = sgprocmanagersha::sha256( stitchedStr.c_str(), stitchedStr.size() ); // existing line 330
```
**New insertion (before line 328):**
```cpp
sgns::sgprocmanagerquant::QuantizeFloatBuffer( stitchedOutput.data(), stitchedOutput.size() );
if ( execCtx.rawOutputCapture ) { /* capture stitchedOutput bytes */ }
```
The other 7 "chained" MNN types (Bool, Buffer, Image, String, Texture1D, TextureCube, Volume — e.g. `_image.cpp:104-110`) get ONLY the per-chunk insertion — their combined hash is `sha256(previousHash + currentChunkHashHex)`, a pure function of already-quantized chunk hashes, so no second insertion point exists there (see Anti-Pattern 3 in ARCHITECTURE.md — do not add a second insertion for these 7 files).

**Exact per-file line numbers** (from research, verify each against live file before editing):
`_float.cpp:307,330` · `_int.cpp:~272,~295` · `_bool.cpp:~334` (chunk only) · `_buffer.cpp:~265` (chunk only) · `_image.cpp:104-105` (chunk only) · `_string.cpp:~142` (chunk only) · `_texture1d.cpp:~406` (chunk only) · `_tensor.cpp:~357,~380` · `_texturecube.cpp:~475,~509` (chunk only, two call sites) · `_volume.cpp:~516` (chunk only) · `_mat2.cpp:~334,~357` · `_mat3.cpp:~334,~357` · `_mat4.cpp:~334,~357`.

---

### `processing_processor_render.cpp` (modified, processor, streaming/transform)

**Analog:** itself — single combined-hash call site, no chunking (`chunkhashes` param explicitly ignored via `(void)chunkhashes;` at line 1999).

**Existing readback + hash** (lines 2133-2167):
```cpp
std::vector<uint8_t> readbackBytes;
if ( !Readback( renderTarget, readbackBytes, errorOut ) )         // line 2134
{
    // error path
}
// ... (line ~2149: size_t outputSize = readbackBytes.size();)
result.hash = sgns::sgprocmanagersha::sha256( readbackBytes.data(), readbackBytes.size() ); // line 2163
// line 2167: output_buffers built FROM readbackBytes
```
**New insertion (before line 2163, after Readback() returns):**
```cpp
sgns::sgprocmanagerquant::QuantizeByteBuffer( readbackBytes.data(), readbackBytes.size() );
if ( execCtx.rawOutputCapture )
{
    // capture readbackBytes (post-quantize) + pre-quantize copy if needed
}
result.hash = sgns::sgprocmanagersha::sha256( readbackBytes.data(), readbackBytes.size() );
```
Note: unlike MNN, `readbackBytes` is already a locally-owned `std::vector<uint8_t>` (not a `const*` into foreign memory), so quantization can mutate it in place — no copy needed here (contrast with the MNN `Anti-Pattern 2` constraint).

---

### `SGProcessingManager/include/artifacts/artifact_serializer.hpp` / `.cpp` (modified — new raw-bytes section)

**Analog:** the file's own existing `SerializeArtifact`/`SerializeManifest` (full header read, lines 1-68).

**Existing fixed-layout convention to extend** (lines 24-55):
```cpp
static constexpr size_t ARTIFACT_SERIALIZED_SIZE = 33880;
static constexpr size_t MANIFEST_SERIALIZED_SIZE = 5649;

std::vector<uint8_t> SerializeArtifact( const Artifact &artifact );
bool DeserializeArtifact( const std::vector<uint8_t> &bytes, Artifact &out );
std::vector<uint8_t> SerializeManifest( const ExecutionManifest &manifest );
bool DeserializeManifest( const std::vector<uint8_t> &bytes, ExecutionManifest &out );
```
**Pattern to copy for the new raw-bytes section:** per D-01/D-07 (capture-file-format decision in CONTEXT.md), do NOT touch `Artifact`/`ExecutionManifest`'s own fixed-size layout or `ARTIFACT_SERIALIZED_SIZE`/`MANIFEST_SERIALIZED_SIZE` constants — those stay exactly as-is (ARTF-05 contract, untouched per research Pattern 4). Instead, add a NEW function/section (likely in the new `tools/capture/capture_file_format.hpp`, not in `artifact_serializer.hpp` itself) that:
1. Calls existing `SerializeArtifact()`/`SerializeManifest()` unchanged for the metadata+hash portion.
2. Appends a new variable-length raw-bytes section (length-prefixed, little-endian, matching this file's "fixed-field, fixed-offset, little-endian" doc-comment convention at lines 2-9) containing the pre-/post-quantization byte buffers captured via the new `rawOutputCapture` callback.
Decide (per CONTEXT.md's Claude's-discretion note) whether this new section needs its own magic-number/version tag — follow whatever convention `SerializeManifest`'s "manifestHash zeroed before serialization, restored afterward" self-hash trick at lines 47-49/57-64 suggests as this codebase's general forward-compat discipline (explicit, documented field ordering, not implicit).

**Error handling / round-trip convention:** `DeserializeArtifact`/`DeserializeManifest` return `bool` (false on size mismatch) rather than throwing — mirror this in the new capture-file section's deserialize path in `capture_file_format.hpp`.

---

### `SGProcessingManager/tools/capture/capture_harness.cpp` (new, CLI entry point, batch/request-response)

**No exact in-repo analog** (first standalone CLI tool in this module — existing executables are GTest binaries under `test/`). Nearest role-match: the `ProcessingManager::Process()` calling convention already used by test/dispatch code.

**Core pattern to copy — the exact overload to call** (`include/processingbase/ProcessingManager.hpp:105-109`, read in full):
```cpp
outcome::result<ProcessOutput> Process( std::shared_ptr<boost::asio::io_context> ioc,
                                        std::vector<std::vector<uint8_t>>       &chunkhashes,
                                        sgns::ModelNode                         &model,
                                        std::vector<std::string>                &output_locations,
                                        ExecutionContext                        &externalExecCtx );
```
This is the exact overload already built "for exactly this purpose" per research Pattern 4 — construct a local `ExecutionContext`, set `rawOutputCapture` to a lambda that accumulates bytes, call this overload, then serialize `ProcessOutput` (artifacts + manifest + combinedHash) via `SerializeArtifact`/`SerializeManifest` plus the new raw-bytes section from `capture_file_format.hpp`.

**`--repeat N` self-check (D-04/D-05):** run the above call N times in a loop, compare each run's `chunkhashes` and `combinedHash` for exact equality; abort and write no file on any mismatch (D-05) — no existing analog for this loop-and-compare shape in this codebase; implement directly per CONTEXT.md D-04/D-05.

**CLI flag parsing:** no existing dependency/convention found in `SGProcessingManager` for CLI arg parsing (CONTEXT.md explicitly defers exact flag names/parser to discretion) — a simple hand-rolled `argv` loop is consistent with this codebase's general "no new dependency without justification" pattern (seen in `sgprocmanagersha`/`sgprocmanagerquant` avoiding unnecessary deps).

---

### `SGProcessingManager/tools/capture/capture_diff.cpp` (new, CLI entry point, batch/transform)

**No analog found.** First diff-style tool in this codebase. Use `DeserializeArtifact`/`DeserializeManifest` (same header as above) to parse both capture files, then compute stats: byte-exact match / max delta / DIFF-02's percentage-of-elements-exceeding-threshold (fixed small epsilon per D-07 + discretion note) / DIFF-03's per-artifact chunk-hash match booleans. Emit both console text and JSON (D-06) — no existing JSON-emission convention found in `SGProcessingManager` itself; `nlohmann_json` is already a dependency of `sgprocmanagertypes` (`src/util/CMakeLists.txt:44`), so reuse `nlohmann::json` for the `--json` output rather than hand-rolling JSON serialization.

---

### `SGProcessingManager/tools/capture/CMakeLists.txt` + `test/capture/CMakeLists.txt` (config)

**Analog for the two `add_executable()` CLI targets (no `add_test`):** `test/capability/CMakeLists.txt` (lines 1-25) for the target-definition shape (include dirs, `target_link_libraries` against `sgprocmanagerlogger`/`sgprocmanagersha`/`sgprocmanagertypes` + new `sgprocmanagerquant` + `ProcessingBase`), minus its `add_test(...)` call (lines 27-29) — `tools/capture/` targets must NOT be registered with CTest per D-Pattern-5 in ARCHITECTURE.md.

**Analog for the thin CTest smoke test:** `SuperGenius/test/src/processing_dispatch/CMakeLists.txt` (full file, 33 lines) — mirrors its `addtest(...)` macro usage, `set_tests_properties(... WORKING_DIRECTORY ...)`, and the `add_custom_command(... POST_BUILD ... copy_if_different ...)` fixture-copying convention if the smoke test needs fixture files copied next to the built test binary. Also mirror `test/capability/CMakeLists.txt`'s explicit `add_executable` + `add_test(NAME ... COMMAND ...)` + `target_link_libraries(... GTest::gtest_main ...)` shape for the GTest structure itself.

## Shared Patterns

### "Mirror sha256's namespace/library shape" (applies to quantization.hpp/.cpp + CMake target)
**Source:** `SGProcessingManager/include/util/sha256.hpp` (full file) + `src/util/CMakeLists.txt:14-26`
**Apply to:** `quantization.hpp`, `quantization.cpp`, new `sgprocmanagerquant` CMake target
```cpp
namespace sgns::sgprocmanager<name> { std::vector<uint8_t>|void <Function>(...); }
```

### "Opt-in, no-op-by-default ExecutionContext callback field" (applies to the new capture hook)
**Source:** `SGProcessingManager/include/execution/execution_context.hpp:131,143` (`progressCallback` field + its `NoOp()` treatment)
**Apply to:** the new `rawOutputCapture` field — same `std::function<...>` shape; UNLIKE `progressCallback`, must stay `nullptr` in `NoOp()` (production/test callers must pay zero cost unless capture_harness explicitly sets it).

### "Copy-then-quantize-then-hash, never mutate MNN's tensor buffer in place" (Anti-Pattern 2, ARCHITECTURE.md)
**Source:** ARCHITECTURE.md Anti-Pattern 2 + `_float.cpp:272` (`const float *data = procresults->host<float>();`)
**Apply to:** all 13 MNN processor per-chunk insertion points — always copy into a locally-owned `std::vector<float>` before calling `QuantizeFloatBuffer`. Render's `readbackBytes` is the one exception (already locally owned, safe to mutate in place).

### "Deterministic fixed-layout binary serialization, bool-return round-trip" (applies to capture_file_format.hpp)
**Source:** `SGProcessingManager/include/artifacts/artifact_serializer.hpp` (full file)
**Apply to:** the new raw-bytes section appended after `SerializeArtifact`/`SerializeManifest` output — same little-endian, fixed-offset discipline, `bool Deserialize...(bytes, out)` signature returning false (not throwing) on malformed input.

### "Standalone CLI executable, no add_test, thin separate CTest smoke test alongside" (Pattern 5, ARCHITECTURE.md)
**Source:** `SGProcessingManager/test/capability/CMakeLists.txt` (target shape) + `SuperGenius/test/src/processing_dispatch/CMakeLists.txt` (fixture-copy + WORKING_DIRECTORY convention)
**Apply to:** `tools/capture/CMakeLists.txt` (2 `add_executable`, no `add_test`) and `test/capture/CMakeLists.txt` (1 `add_executable` + `add_test`, GTest-based).

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `tools/capture/capture_diff.cpp` | CLI entry point | batch/transform | First diff-style/comparison CLI tool in this codebase; no existing "read 2 files, compute stats, emit JSON+console" precedent. Use `nlohmann_json` (already a dependency elsewhere) for `--json` output and `DeserializeArtifact`/`DeserializeManifest` for parsing. |
| `tools/capture/capture_harness.cpp` (CLI arg parsing only) | CLI entry point | request-response | No existing CLI flag-parsing convention in `SGProcessingManager`; CONTEXT.md explicitly defers exact flag names/parser to discretion — a hand-rolled `argv` loop is consistent with the codebase's general no-new-dependency bias. |

## Metadata

**Analog search scope:** `SGProcessingManager/include/util/`, `SGProcessingManager/src/util/`, `SGProcessingManager/include/execution/`, `SGProcessingManager/include/artifacts/`, `SGProcessingManager/src/processors/`, `SGProcessingManager/test/capability/`, `SuperGenius/test/src/processing_dispatch/`
**Files scanned:** sha256.hpp, execution_context.hpp, artifact_serializer.hpp, ProcessingManager.hpp, src/util/CMakeLists.txt, test/capability/CMakeLists.txt, processing_dispatch/CMakeLists.txt, processing_processor_mnn_float.cpp, processing_processor_render.cpp (grep + targeted reads)
**Pattern extraction date:** 2026-08-10
