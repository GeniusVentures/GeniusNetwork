# Phase 3: minio-cpp Integration & S3Client Adapter - Pattern Map

**Mapped:** 2026-10-21
**Files analyzed:** 18 (14 new, 4 modified — hpp/cpp pairs counted per file)
**Analogs found:** 16 exact/role-match + 2 partial / 18

All analog paths below were verified git-tracked (`git ls-files` run inside `thirdparty/` and `thirdparty/sgns-blockstore/` — every named path printed). No gitignored/mirror paths are referenced.

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `thirdparty/minio-cpp` (submodule @ v1.0.0) | config (dep source) | — | `thirdparty/.gitmodules:126-128` (shaderc, absolute URL) | exact |
| `thirdparty/pugixml` (submodule @ v1.16) | config (dep source) | — | `thirdparty/.gitmodules:114-116` (json, absolute URL) | exact |
| `thirdparty/.gitmodules` (modified: +2 entries) | config | — | shaderc/json entries `.gitmodules:114-128` | exact |
| `thirdparty/build/CommonTargets.cmake` (modified: +pugixml, +minio-cpp entries; json export var; sgns-blockstore gains minio wiring) | config (build orchestration) | batch | shaderc entry `:420-448`; rocksdb entry `:141-174`; sgns-blockstore entry `:779-815` | exact |
| `thirdparty/sgns-blockstore/src/S3Client.hpp` (NEW, internal, not installed) | model (interface + config/options types) | request-response | `include/sgns-blockstore/BlockStore.hpp:61-137` + `Options.hpp` + `Cid.hpp:23-37` | exact |
| `thirdparty/sgns-blockstore/src/MinioS3Client.hpp` (NEW) | service (impl header, pimpl) | request-response | `include/sgns-blockstore/LocalBlockStore.hpp` (pimpl header, :28-36 class doc, :96-110 Open factory) | exact |
| `thirdparty/sgns-blockstore/src/MinioS3Client.cpp` (NEW) | service (SDK adapter, one-place status mapping) | request-response | `src/LocalBlockStore.cpp` — `MapStatus :154-178`, `Impl :186-198`, `Open :232-263` | exact |
| `thirdparty/sgns-blockstore/src/InMemoryS3Client.hpp` (NEW) | fake service (stateful map) | request-response (in-memory) | `include/sgns-blockstore/MemoryBlockStore.hpp` + `FaultController.hpp:14-20,39-55` | exact |
| `thirdparty/sgns-blockstore/src/InMemoryS3Client.cpp` (NEW) | fake service impl | request-response (in-memory) | `src/MemoryBlockStore.cpp` — `FaultGate :40-53`, `Put :56-84` | exact |
| `thirdparty/sgns-blockstore/CMakeLists.txt` (modified: find_package(miniocpp)) | config | — | own `find_package(RocksDB CONFIG REQUIRED)` no-version pattern `:17-21` | exact |
| `thirdparty/sgns-blockstore/src/CMakeLists.txt` (modified: +3-4 sources, +miniocpp link) | config | — | existing `add_library`/`target_link_libraries` `:1-15` | exact |
| `thirdparty/sgns-blockstore/test/CMakeLists.txt` (modified: +4-5 test targets) | config | — | `addtest()` blocks `test/CMakeLists.txt:1-45` | exact |
| `thirdparty/sgns-blockstore/test/minio_cpp_spike_test.cpp` (NEW — D-11 day-one spike; name discretionary) | test (entrance-criterion spike) | request-response | `test/cid_spike_test.cpp:1-17` (assertion-bar header) | exact |
| `thirdparty/sgns-blockstore/test/in_memory_s3_client_test.cpp` (NEW) | test | request-response | `test/memory_block_store_test.cpp` (helpers `:53-64`, fixture `:66-78`, kit instantiations `:381-390`) | exact |
| `thirdparty/sgns-blockstore/test/minio_s3_client_test.cpp` (NEW — stub matrix + env-gated live tier) | test | request-response | `test/local_block_store_crash_test.cpp` (taxonomy asserts, `NextUniqueDir :73-78`) + conformance-kit loud skips | role-match |
| `thirdparty/sgns-blockstore/test/LoopbackHttpStub.hpp/.cpp` (NEW) | test utility (raw-socket scripted HTTP server) | request-response / byte-stream | **no in-tree server analog** — nearest: crash-test corruption forge `local_block_store_crash_test.cpp:110-151` | partial |
| `thirdparty/sgns-blockstore/test/MinioServerHarness.hpp/.cpp` (NEW) | test utility (child-process lifecycle, env-gated) | process I/O | **no child-process analog in tree** — nearest: `NextUniqueDir :73-78` + kit loud-skip `BlockStoreConformanceTests.hpp:258-262` | partial |
| `thirdparty/sgns-blockstore/test/api_hygiene_test.cpp` (modified: extended guard) | test (compile-time guard) | compile-time | itself — include-everything `:36-47`, SFINAE traits `:50-115` | exact |

---

## Pattern Assignments

### `thirdparty/sgns-blockstore/src/S3Client.hpp` (model/interface, request-response) — internal, NOT installed (D-04)

**Analogs:** `BlockStore.hpp` (interface shape), `Options.hpp` (options struct shape), `Cid.hpp` (result alias — MANDATORY), `Durability.hpp` (PutOutcome mirror target for D-02)

**Result-envelope pattern — copy verbatim from `Cid.hpp:23-37`** (Phase-1 landmine: every new library header must reuse this alias; any other outcome spelling trips the guard-tested `policy::terminate` deviation):

```cpp
// include/sgns-blockstore/Cid.hpp:23-37
namespace outcome = libp2p::outcome;

template <class R, class S = std::error_code,
          class NoValuePolicy = libp2p::outcome::policy::terminate>
using result = libp2p::outcome::basic_result<R, S, NoValuePolicy>;
```

The internal header reaches these via `#include <sgns-blockstore/Cid.hpp>` (installed header, already public — internal code may include public headers). Note `header_hygiene_check.cmake:22-28` bans `minio` includes only under `include/sgns-blockstore/`; `src/` headers are unrestricted, but keep the interface itself SDK-free anyway (SC2/BACK-06).

**Interface declaration pattern — copy shape from `BlockStore.hpp:61-137`** (pure-virtual class, Doxygen `@brief/@param/@return` per op, `virtual ~... = default`, options-by-struct with `{}` default):

```cpp
// include/sgns-blockstore/BlockStore.hpp:83-98
virtual result<PutOutcome, BlockStatus> Put(
    const Cid& cid, gsl::span<const uint8_t> bytes,
    const WriteOptions& options = {})
    = 0;

virtual result<Block, BlockStatus> Get(
    const Cid& cid, const ReadOptions& options = {})
    = 0;
```

The S3 seam adapts this to ~5 ops (Put/Get/Head/Delete + config) over `std::string` keys and byte buffers — D-01 (one Put with `createOnly` option), D-03 (delete IS an op here, never on BlockStore).

**Options-struct pattern — copy from `Options.hpp:25-43`** (plain aggregate, defaulted members, deadline field, doc-note discipline):

```cpp
// include/sgns-blockstore/Options.hpp:25-29
struct ReadOptions
{
    std::chrono::steady_clock::time_point deadline; ///< abort waiting after this point
    bool verify = true; ///< re-verify returned bytes against the CID (default on)
};
```

`PutObjectOptions{ bool createOnly = false; }` and `S3ClientConfig{ endpoint, port, region, useTls, tlsVerify, pathStyle... }` mirror this aggregate style (CONTEXT "agent's Discretion" governs the exact field set).

**D-02 payload mirror — copy shape from `Durability.hpp:34-39`**:

```cpp
// include/sgns-blockstore/Durability.hpp:34-39
struct PutOutcome
{
    DurabilityLevel achieved; ///< the verified durability level of the write
    bool alreadyPresent;      ///< true when the block was already stored (identical re-put)
};
```

The adapter's S3-level put result (success slot carrying `alreadyPresent=true` on 412) mirrors this two-field shape so Phase-4 SC2 maps 1:1 with zero re-freeze. Whether it reuses `PutOutcome` directly or an S3-local struct is planner discretion; either way the `alreadyPresent` bool-in-success-slot semantic is the frozen part.

---

### `thirdparty/sgns-blockstore/src/MinioS3Client.hpp` + `.cpp` (service, request-response)

**Analog:** `LocalBlockStore.hpp` / `LocalBlockStore.cpp` — the Phase-2 pimpl + one-place status-mapping precedent. `MinioS3Client.cpp` is where ALL `miniocpp::*` usage lives (exactly as all `rocksdb::*` lives in `LocalBlockStore.cpp:1-4` header comment declares: "ALL rocksdb::* usage lives in this TU").

**Pimpl header pattern — copy from `LocalBlockStore.hpp:96-110` + out-of-line dtor `:80`**:

```cpp
// include/sgns-blockstore/LocalBlockStore.hpp:96-110
static result<std::unique_ptr<LocalBlockStore>, BlockStatus> Open(
    const LocalBlockStoreOptions& options);
```

```cpp
// src/LocalBlockStore.cpp:186-198 — every SDK type behind the Impl
class LocalBlockStore::Impl
{
public:
    ...
    rocksdb::DB* db_ = nullptr;
    rocksdb::ColumnFamilyHandle* blocks_ = nullptr;
    ...
};
```

`MinioS3Client::Impl` holds `minio::s3::Client` + `BaseUrl` + creds provider the same way. Constructor takes `S3ClientConfig`, mirrors `Open`'s `result<..., BlockStatus>` factory shape (config-programmer-error → `throw std::invalid_argument`, same as `LocalBlockStore.cpp:236-242` empty-path check).

**ONE-PLACE status mapping — copy structure from `LocalBlockStore.cpp:154-178` (`MapStatus`)**. This is the single most important pattern for BACK-06/SC4. Minio's version classifies error STRINGS (research Pattern 2 table) instead of `rocksdb::Status` codes:

```cpp
// src/LocalBlockStore.cpp:154-178 (verbatim shape to adapt)
BlockStatus MapStatus(const rocksdb::Status& status,
                      const std::string& context)
{
    if (status.IsNotFound())
    {
        return BlockStatus{StatusClass::NotFound, BlockSource::Local,
                           context};
    }
    if (status.IsCorruption())
    {
        return BlockStatus{StatusClass::Corrupt, BlockSource::Local,
                           context + ": " + status.ToString()};
    }
    // every environment-class failure is non-authoritative.
    return BlockStatus{StatusClass::TemporarilyUnavailable,
                       BlockSource::Local,
                       context + ": " + status.ToString()};
}
```

Minio mapper: `NoSuchKey:`/`NoSuchBucket:` prefix → NotFound; `AccessDenied:` → Unauthorized; `PreconditionFailed:` (AND the bare `"server failed with HTTP status code 412"` string) → **not a failure** — return the D-02 success slot with `alreadyPresent=true` before MapStatus is ever consulted; everything else → TemporarilyUnavailable with the message preserved (`BlockSource::Remote`). Never `NotFound` on unrecognized strings (SC4). Anonymous-namespace placement + Doxygen comment block exactly as `MapStatus` does.

**Per-op shape — copy from `LocalBlockStore.cpp:291-364` (`Put`)**: entry gate → fault/explicit error mapping → op → map every failure through the ONE function → success payload. Note `:332` computes `already_present` BEFORE any write (read-before-write; Minio gives it for free via the 412) and `:364` `return PutOutcome{DurabilityLevel::LocalCommitted, already_present};`.

---

### `thirdparty/sgns-blockstore/src/InMemoryS3Client.hpp` + `.cpp` (fake service, D-05)

**Analogs:** `MemoryBlockStore.hpp/.cpp` (stateful map backend) + `FaultController.hpp` (fault-scripting seam philosophy)

**Fault-scripting seam — copy from `FaultController.hpp:14-20, 39-55`** (enum of fault kinds + SetFault/GetFault virtuals; D-05 extends this to per-OP scripting — a `nextResponse` table keyed by op kind rather than one global kind — but the naming/Doxygen/@note "production code MUST NOT call" discipline carries over verbatim):

```cpp
// include/sgns-blockstore/FaultController.hpp:14-20
enum class FaultKind
{
    None,         ///< normal operation
    Unavailable,  ///< all ops fail TemporarilyUnavailable (never NotFound, never false)
    CorruptData,  ///< Get returns bytes that fail CID verification
    Unauthorized, ///< all ops fail Unauthorized (auth/permission failure)
};
```

**Stateful-map + fault-gate pattern — copy from `MemoryBlockStore.cpp:40-53` (`FaultGate`) and `:56-84` (`Put`)**:

```cpp
// src/MemoryBlockStore.cpp:40-53
std::optional<BlockStatus> FaultGate(FaultKind fault)
{
    switch (fault)
    {
        case FaultKind::Unavailable:
            return BlockStatus{StatusClass::TemporarilyUnavailable,
                               BlockSource::Memory,
                               "fault injection: backend unavailable"};
        ...
        default:
            return std::nullopt;
    }
}
```

```cpp
// src/MemoryBlockStore.cpp:82-84 — alreadyPresent computed pre-write
const bool already_present = storage_.find(cid) != storage_.end();
storage_[cid] = std::vector<uint8_t>(bytes.begin(), bytes.end());
return PutOutcome{DurabilityLevel::LocalCommitted, already_present};
```

The fake: `std::map<std::string, std::vector<uint8_t>> objects_`; `createOnly=true` Put over an existing key returns the SUCCESS slot with `alreadyPresent=true` WITHOUT writing (D-01/D-02 enforcement); scripted fault entries return adapter-level taxonomy results directly (research Pattern 3 — faults map to taxonomy outcomes, not raw bytes, so Phase 5 composes on this surface). Header-member shape mirrors `MemoryBlockStore.hpp:79-81` (`storage_` map + `fault_` seam state with the "never read by production paths" comment).

---

### `thirdparty/build/CommonTargets.cmake` (modified — pugixml + minio-cpp entries, json export, sgns-blockstore wiring)

**Analog 1 — shaderc entry `:420-448`**: THE precedent for minio-cpp (dep mechanism runs inside the ExternalProject step; short BINARY_DIR for MAX_PATH; explicit skip flags). Copy the comment discipline verbatim:

```cmake
# thirdparty/build/CommonTargets.cmake:429-448 (verbatim, adapt names)
    # Short binary dir: the default (<prefix>/src/shaderc-build) pushes spirv-tools'
    # MSBuild .tlog paths past the Windows MAX_PATH (260) limit on runners without
    # OS long-path support (worst path 272 -> 254 chars). Must stay directly under a
    # */src directory: build.yml's tarball step excludes build trees via
    # --exclude='./*/src' — any other location leaks the whole glslang/SPIRV-Tools
    # object tree into the release tarballs and blows the 2 GiB asset limit (HTTP 422).
    BINARY_DIR "${CMAKE_CURRENT_BINARY_DIR}/scb/src"
       PATCH_COMMAND
        ${Python3_EXECUTABLE} "${THIRDPARTY_DIR}/shaderc/utils/git-sync-deps"
       CMAKE_CACHE_ARGS
    -DCMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
    -DSHADERC_SKIP_TESTS:BOOL=ON
    -DSHADERC_SKIP_EXAMPLES:BOOL=ON
    ...
    ${_CMAKE_COMMON_CACHE_ARGS}
```

minio-cpp mirrors: `BINARY_DIR "${CMAKE_CURRENT_BINARY_DIR}/mcb/src"` (research sketch — `miniocpp-deps.cmake` clones into `<binary>/_deps/`, same MAX_PATH trap), NO PATCH_COMMAND (D-12: upstream's `miniocpp-deps.cmake` runs as-is at configure), explicit `-DMINIO_CPP_TEST:BOOL=OFF -DMINIO_CPP_ENABLE_RDMA:BOOL=OFF` mirroring the SHADERC_SKIP_* self-documenting flags.

**Analog 2 — rocksdb entry `:141-174`**: DEPENDS + BUILD_BYPRODUCTS + config-dir export triple:

```cmake
# thirdparty/build/CommonTargets.cmake:167-173 (verbatim shape)
    DEPENDS snappy
    BUILD_BYPRODUCTS
    "${CMAKE_CURRENT_BINARY_DIR}/rocksdb/lib/librocksdb.a"
    "${CMAKE_CURRENT_BINARY_DIR}/rocksdb/lib/cmake/rocksdb/RocksDBConfig.cmake"
)
set(_FINDPACKAGE_ROCKSDB_DIR "${CMAKE_CURRENT_BINARY_DIR}/rocksdb/lib/cmake/rocksdb")
```

minio-cpp byproduct note: artifact is `libminio.a`/`minio.lib` (target `miniocpp`, `OUTPUT_NAME minio`) — never `libminiocpp.a`. Export: `set(_FINDPACKAGE_MINIOCPP_CONFIG_DIR "${CMAKE_CURRENT_BINARY_DIR}/minio-cpp/lib/cmake/miniocpp")` per the repo-wide `_FINDPACKAGE_*_CONFIG_DIR` naming convention (`CommonCompilerOptions.cmake:120-122` documents that all such hints hardcode the `lib` layout pinned by `-DCMAKE_INSTALL_LIBDIR:STRING=lib`).

**Analog 3 — sgns-blockstore entry `:779-815`** — the entry being MODIFIED. Gains `-Dminiocpp_DIR:PATH=${_FINDPACKAGE_MINIOCPP_CONFIG_DIR}` (sorted among the alphabetized `-D..._DIR` args, `:787-802` block), `-Dpugixml_DIR`/`-Dnlohmann_json_DIR` not needed here (they're minio-cpp's deps, not the lib's), and `DEPENDS` line `:811` becomes `DEPENDS libp2p rocksdb minio-cpp`. **CRITICAL: the `-DTESTING:BOOL=ON` arg at `:810` MUST stay the LAST cache arg** — comment block at `:804-809` explains why (`_CMAKE_COMMON_CACHE_ARGS` forces `-DBUILD_TESTING:BOOL=OFF`; later cache args win; the repo gate is `TESTING`):

```cmake
# thirdparty/build/CommonTargets.cmake:803-815 (verbatim)
    ${_CMAKE_COMMON_CACHE_ARGS}
    # MUST stay the LAST cache arg: _CMAKE_COMMON_CACHE_ARGS forces
    # -DBUILD_TESTING:BOOL=OFF above, and later cache args win under
    # ExternalProject's initial-cache FORCE semantics. The repo's test gate
    # is named TESTING (never BUILD_TESTING), so this is what re-enables
    # tests through the superbuild.
    -DTESTING:BOOL=ON
    DEPENDS libp2p rocksdb
    BUILD_BYPRODUCTS
    "${CMAKE_CURRENT_BINARY_DIR}/sgns-blockstore/lib/${CMAKE_STATIC_LIBRARY_PREFIX}sgns-blockstore${CMAKE_STATIC_LIBRARY_SUFFIX}"
)
set(_FINDPACKAGE_SGNS_BLOCKSTORE_CONFIG_DIR "${CMAKE_CURRENT_BINARY_DIR}/sgns-blockstore/lib/cmake/sgns-blockstore")
```

**Analog 4 — json entry `:836-846`** — currently exports NOTHING; Phase 3 adds `set(_FINDPACKAGE_JSON_CONFIG_DIR "${CMAKE_CURRENT_BINARY_DIR}/json/lib/cmake/nlohmann_json")` after it (path per nlohmann_json's installed config layout; verify during the day-one spike) so `miniocpp-deps.cmake`'s `find_package(nlohmann_json CONFIG REQUIRED)` resolves inside the ExternalProject.

**Analog 5 — pugixml entry**: simplest precedents are `Vulkan-Headers` (`:369-377`) or `vk-bootstrap` (`:406-418`) — `ExternalProject_Add` + `PREFIX` + `SOURCE_DIR` + `-DCMAKE_INSTALL_PREFIX` + `${_CMAKE_COMMON_CACHE_ARGS}` + own export var `set(_FINDPACKAGE_PUGIXML_CONFIG_DIR ...)`, then `-Dpugixml_DIR:PATH=${_FINDPACKAGE_PUGIXML_CONFIG_DIR}` inside the minio-cpp entry's cache args (alphabetized placement per the `AsyncIOManager :747-782` convention).

---

### `thirdparty/.gitmodules` + submodules `minio-cpp`/`pugixml` (config)

**Analog:** absolute-URL upstream entries — `.gitmodules:114-116` (json) and `:126-128` (shaderc):

```gitconfig
# thirdparty/.gitmodules:114-116 (verbatim)
[submodule "json"]
	path = json
	url = https://github.com/nlohmann/json.git
# :126-128
[submodule "shaderc"]
	path = shaderc
	url = https://github.com/google/shaderc.git
```

New entries use upstream absolute URLs (`https://github.com/minio/minio-cpp.git`, `https://github.com/zeux/pugixml.git`) — NOT the `../` relative GNUS-fork form (`.gitmodules:99-101` sgns-blockstore) — pinned by checking out the tag (`v1.0.0`, `v1.16`) in the submodule; the pin lives in the submodule commit SHA the superproject records. D-12: no fork URLs.

---

### `thirdparty/sgns-blockstore/CMakeLists.txt` + `src/CMakeLists.txt` + `test/CMakeLists.txt` (modified)

**Analog:** the existing files themselves.

Root `CMakeLists.txt:17-21` — the no-version `find_package(<Name> CONFIG REQUIRED)` pattern (Phase-2 dual-compat lesson, BACK-03 comment) is exactly how `find_package(miniocpp CONFIG REQUIRED)` lands (guard with `if(TESTING)`-style scope NOT needed — minio is a production link dep):

```cmake
# thirdparty/sgns-blockstore/CMakeLists.txt:17-21 (verbatim)
# NO version argument (BACK-03 dual-compat): the installed config version
# file is COMPATIBILITY SameMajorVersion, so a versioned request would
# reject a consumer-side 11.1.2 install against this 9.4 build.
find_package(RocksDB CONFIG REQUIRED)
```

`src/CMakeLists.txt:1-15` — add the new `.cpp`s to the static lib and the SDK link. Key decision encoded here: `RocksDB::rocksdb` is `PUBLIC` (`:11`) because it appears in installed headers via the package-config `find_dependency`; miniocpp appears in NO installed header (D-04), so its link is `PRIVATE`:

```cmake
# thirdparty/sgns-blockstore/src/CMakeLists.txt:8-12 (verbatim shape to extend)
target_link_libraries(sgns-blockstore
    PUBLIC p2p::p2p_cid
    PUBLIC RocksDB::rocksdb
    PRIVATE miniocpp::miniocpp   # NEW — internal-only; never in an installed header
)
```
(target name per miniocpp's exported config — verify exact spelling during the spike.)

`test/CMakeLists.txt:1-45` — the `addtest()` + `target_link_libraries` block pattern; new test targets copy `local_block_store_crash_test` (`:31-39`) which links an extra PRIVATE dep beyond the lib (precedent for linking `miniocpp` + the stub/harness objects into test binaries). The env-gated MinIO tier does NOT get a CMake gate — it's one target, runtime-skipped (D-07):

```cmake
# thirdparty/sgns-blockstore/test/CMakeLists.txt:31-39 (verbatim shape)
addtest(local_block_store_crash_test local_block_store_crash_test.cpp)
target_link_libraries(local_block_store_crash_test
    sgns-blockstore
    p2p::p2p_cid
    RocksDB::rocksdb
)
```

---

### `thirdparty/sgns-blockstore/test/minio_cpp_spike_test.cpp` (D-11 day-one spike)

**Analog:** `cid_spike_test.cpp:1-17` — the Phase-1 entrance-criterion spike whose header comment states the assertion bar VERBATIM before any code. Copy that discipline: the spike TU's header lists the D-11 trio bar (conditional `If-None-Match:*` observed on the wire via the stub's captured bytes → 412 → `alreadyPresent=true`; BaseUrl fields path-style/HTTPS/region verified; TLS on/off smoke against the local endpoint):

```cpp
// thirdparty/sgns-blockstore/test/cid_spike_test.cpp:1-17 (verbatim discipline)
/*
 * C1 CID-dependency spike - the Phase-1 entrance criterion (decision D-06).
 *
 * Part 3 assertion bar, pre-refined per research Pitfall 1 and stated here
 * verbatim so the bar is not discovered mid-spike:
 *   (a) this TU compiles and links against p2p::p2p_cid alone;
 *   ...
 */
```

Also copy: assertions as plain `TEST(...)` with given/when/then Doxygen comments (`cid_spike_test.cpp:60-66`), and its `test/CMakeLists.txt:12-16` registration (`addtest(cid_spike_test ...)` + link `sgns-blockstore p2p::p2p_cid` — the spike additionally links `miniocpp`).

---

### `thirdparty/sgns-blockstore/test/in_memory_s3_client_test.cpp` (SC3 fake tests)

**Analog:** `memory_block_store_test.cpp` — copy the file skeleton wholesale:

- Header Doxygen block naming the decisions proven (`:1-14`)
- Include order: gtest → std → sgns-blockstore → libp2p (`:16-27`)
- Anonymous-namespace `using` block (`:29-45`), `SpanOf`/`MakeCid` helpers (`:53-64` — S3 version needs only a bytes helper; keys are plain strings)
- Fixture with member-initializers (`:66-78`, note the "no default constructor" comment style)
- Plain GTest discipline: `EXPECT_TRUE(result)` + manual `.value()/.error()`, zero outcome macros (`:12-13` D-11 note)
- Taxonomy assertion idiom — `ASSERT_FALSE(res); EXPECT_EQ(res.error().code, StatusClass::NotFound); EXPECT_NE(res.error().source, BlockSource::Unknown);`

```cpp
// thirdparty/sgns-blockstore/test/memory_block_store_test.cpp:53-64 (verbatim shape)
gsl::span<const uint8_t> SpanOf(const std::string& s)
{
    return gsl::span<const uint8_t>(
        reinterpret_cast<const uint8_t*>(s.data()), s.size());
}
```

Cases to cover (from CONTEXT D-01/D-02/D-05): 200/404/error round trips; createOnly duplicate → success-slot `alreadyPresent=true` with original bytes intact; each scripted fault kind → its taxonomy class; non-sticky (fault clears → next op succeeds) mirroring the kit's `FaultClearsNoStickyNegativeCache` case.

---

### `thirdparty/sgns-blockstore/test/minio_s3_client_test.cpp` (stub matrix + env-gated live tier)

**Analog 1:** `local_block_store_crash_test.cpp` — the backend-specific suite that asserts the full taxonomy against induced failures. Copy: header "read before touching" comment (`:1-19`), helper-then-fixture layout (`:52-160`), and `NextUniqueDir` (`:73-78`) for the harness's per-test temp dirs (short relative path under the build tree — Windows MAX_PATH):

```cpp
// thirdparty/sgns-blockstore/test/local_block_store_crash_test.cpp:71-78 (verbatim)
// SHORT relative path under the build tree (Windows MAX_PATH); a
// monotonic counter gives every case its own directory.
std::string NextUniqueDir()
{
    static std::atomic<uint64_t> next{0};
    return "test-data/local-blockstore-crash/case-"
         + std::to_string(next.fetch_add(1));
}
```

**Analog 2 (loud labelled skip):** `conformance/BlockStoreConformanceTests.hpp:258-262` — the D-07/D-09 gate pattern for the env-gated MinIO tier (label must be greppable; Phase-5 SC3 inspects this):

```cpp
// thirdparty/sgns-blockstore/test/conformance/BlockStoreConformanceTests.hpp:258-262 (verbatim)
if (!fc)
{
    GTEST_SKIP() << "[fault-conformance] backend does not implement " \
                    "FaultController";
}
```

MinIO tier form: `GTEST_SKIP() << "[SGNS_BLOCKSTORE][MINIO-TIER] binary not provided (set SGNS_BLOCKSTORE_TEST_MINIO_BIN)"` when the env var (research's recommended name) is unset.

Matrix cases (D-08): connection-refused / 5xx / truncated body / garbage response / empty-body-412 vs XML-412 — each asserts its taxonomy class, then a subsequent good op succeeds (no sticky negative cache — mirror the kit's `FaultClearsNoStickyNegativeCache` sequencing).

---

### `thirdparty/sgns-blockstore/test/LoopbackHttpStub.hpp/.cpp` (test utility — raw-socket scripted server)

**No in-tree HTTP-server analog.** Role models for the DISCIPLINE, not the mechanism:

- `local_block_store_crash_test.cpp:110-151` (`CorruptStoredBlock`) — the precedent for a test-only forge that produces GENUINE wire-level faults (byte-flip on real storage) with ASSERT-driven setup and explicit teardown ordering. The stub is the transport-flavored equivalent: accept → read request (capture raw bytes for the spike's header assertion) → send scripted response bytes → close.
- `MemoryBlockStore.cpp:40-53` (`FaultGate`) — the scripting-surface philosophy (named fault kinds → deterministic outcomes).
- Header/impl split + Doxygen `@brief` per `LoopbackHttpStub.hpp` follows every existing utility header; keep it ~150 self-contained lines (research recommendation), raw sockets, `#ifdef _WIN32` WinSock/POSIX split — no new library deps on the test link line beyond ws232 on Windows.

---

### `thirdparty/sgns-blockstore/test/MinioServerHarness.hpp/.cpp` (test utility — env-gated child process)

**No child-process analog in tree** (research confirms: Boost.Process available but not on sgns-blockstore's link line; hand-rolled `#ifdef _WIN32` CreateProcess/POSIX fork-exec recommended). Discipline precedents:

- Loud skip gate: `BlockStoreConformanceTests.hpp:258-262` (above) — harness exposes `bool Available()` + the test emits the labelled skip.
- Per-test temp dirs: `NextUniqueDir` `local_block_store_crash_test.cpp:73-78`.
- Teardown-ordering discipline: `LocalBlockStore::Close` `LocalBlockStore.cpp:270-289` documents WHY the order matters (resource → close → free, idempotent, status-dropped-in-dtor `:211-214`) — harness dtor mirrors: terminate child → wait → remove temp dir, all idempotent.
- Readiness: deadline-bounded poll of `/minio/health/live`, never fixed sleeps (Phase-1 discipline; research Code Examples "Harness readiness poll").
- Fixture pattern for consumers: plain `::testing::Test` subclass with member-initializers (`local_block_store_test.cpp:117` `std::string dir_ = NextUniqueDir();`).

---

### `thirdparty/sgns-blockstore/test/api_hygiene_test.cpp` (modified — extended guard)

**Analog:** itself. Two existing mechanics to extend:

1. **Include-everything block `:36-47`** — unchanged in Phase 3 (no new installed headers; D-04 keeps S3Client.hpp in `src/`). Its EXISTING compile+run with minio-cpp linked into the lib IS the new SC2 proof (research Pattern 1: "if it still compiles with minio-cpp linked into the lib, no SDK type leaked into the installed surface"). Add a comment noting the minio linkage makes this load-bearing.
2. **C++17 SFINAE trait block `:50-115`** — the template to copy for new guards, e.g. asserting `S3Client`-shaped seams stay off public types:

```cpp
// thirdparty/sgns-blockstore/test/api_hygiene_test.cpp:50-63 (verbatim pattern)
template <class T, class = void>
struct HasRemove : std::false_type
{
};
template <class T>
struct HasRemove<T, std::void_t<decltype(&T::Remove)>> : std::true_type
{
};
```

(Note the file header `:33-37`: NO C++20 requires expressions — superbuild pins C++17.) `header_hygiene_check.cmake` needs NO change — its `_banned` list (`:22-28`) already contains `"minio"`.

---

## Shared Patterns

### Result envelope (MANDATORY in every new header)
**Source:** `thirdparty/sgns-blockstore/include/sgns-blockstore/Cid.hpp:23-37`
**Apply to:** `S3Client.hpp`, `MinioS3Client.hpp`, `InMemoryS3Client.hpp`, all test TUs.
Library-local `result<R, S, policy::terminate>` alias only. Guard with `has_value()`/`if (!res)` before `.value()`/`.error()` — `.value()` on failure terminates by design.

### One-place status mapping per backend
**Source:** `src/LocalBlockStore.cpp:154-178` (`MapStatus`), preceded by `src/MemoryBlockStore.cpp`'s single-gate design.
**Apply to:** `MinioS3Client.cpp` (string-prefix classification; unknown → TemporarilyUnavailable, NEVER NotFound; 412 shapes → D-02 success slot BEFORE the mapper runs).

### Fault scripting seam
**Source:** `include/sgns-blockstore/FaultController.hpp` + `src/MemoryBlockStore.cpp:40-53` (`FaultGate`).
**Apply to:** `InMemoryS3Client` (per-op scriptable responses — the D-05 extension of the per-backend-kind original), `LoopbackHttpStub` (scripted wire bytes).

### Loud labelled skip
**Source:** `test/conformance/BlockStoreConformanceTests.hpp:258-262`.
**Apply to:** every env-gated MinIO-tier test (D-07/D-09). Labels greppable: `[SGNS_BLOCKSTORE][MINIO-TIER]`.

### Plain GTest discipline
**Source:** `test/memory_block_store_test.cpp:12-13` (D-11 note), kit header `:15-17`.
**Apply to:** all new test TUs — `EXPECT_TRUE`/`ASSERT_FALSE` + manual `.value()`/`.error()` extraction; zero outcome test macros; given/when/then Doxygen per test.

### Superbuild cache-arg ordering
**Source:** `thirdparty/build/CommonTargets.cmake:803-810` (TESTING-last rule) + `thirdparty/build/CommonCompilerOptions.cmake:100-134` (`_CMAKE_COMMON_CACHE_ARGS`).
**Apply to:** both new entries; the modified sgns-blockstore entry keeps `-DTESTING:BOOL=ON` last. `_CMAKE_COMMON_CACHE_ARGS` goes at the bottom of each new entry's cache args (static/PIC/C++17/CRT/`CMAKE_TOOLCHAIN_FILE` — the latter also neutralizes minio-cpp's `VCPKG_ROOT` auto-toolchain, research Pitfall 5).

### `_FINDPACKAGE_*_CONFIG_DIR` export convention
**Source:** `rocksdb :172`, `sgns-blockstore :815`, `libssh2 :743-745`, plus `CommonCompilerOptions.cmake:120-122` (lib-layout pinning note).
**Apply to:** `_FINDPACKAGE_PUGIXML_CONFIG_DIR`, `_FINDPACKAGE_MINIOCPP_CONFIG_DIR`, `_FINDPACKAGE_JSON_CONFIG_DIR` — all `"${CMAKE_CURRENT_BINARY_DIR}/<prefix>/lib/cmake/<pkg>"` form.

### Short build-tree paths (Windows MAX_PATH)
**Source:** shaderc `BINARY_DIR` comment `CommonTargets.cmake:430-436`; `NextUniqueDir` `local_block_store_crash_test.cpp:71-78`.
**Apply to:** minio-cpp `BINARY_DIR "${CMAKE_CURRENT_BINARY_DIR}/mcb/src"` (its `_deps` clone tree is the new MAX_PATH hazard), harness temp dirs.

### Coding style
**Source:** `Coding Standards.md` (workspace root) + every analog file.
**Apply to:** all new C++ — Ullman braces, PascalCase types/headers (`S3Client.hpp`, `MinioS3Client`, `InMemoryS3Client`), `m_`/trailing-underscore members (`storage_`, `fault_` precedent), Doxygen `@brief/@param/@return/@note` on public interfaces, `#ifndef SGNS_BLOCKSTORE_*_HPP` guards (internal src/ headers keep the same guard style — see `FaultController.hpp:6-7`).

---

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `test/LoopbackHttpStub.hpp/.cpp` | test utility (server) | request-response / byte-stream | No HTTP server exists anywhere in the sgns-blockstore tree; transport code lives behind thirdparty libs. Planner should follow research's ~150-line raw-socket sketch + the fault-forge discipline excerpts above. |
| `test/MinioServerHarness.hpp/.cpp` | test utility (process lifecycle) | process I/O | No child-process spawn/kill code in the repo's test trees (crash tests simulate death in-process). Follow research Pattern 4 + the discipline excerpts above; `#ifdef _WIN32` split. |

Both are test-tree-only utilities — no production-pattern risk from the gap.

## Metadata

**Analog search scope:** `thirdparty/sgns-blockstore/` (include/, src/, test/, test/conformance/, cmake/), `thirdparty/build/` (CommonTargets.cmake, CommonCompilerOptions.cmake), `thirdparty/.gitmodules`. Verified tracked via `git ls-files` in both repos.
**Files scanned:** 20 analog candidates read; 18 target files classified.
**Pattern extraction date:** 2026-10-21
**Notes for planner:** (1) pugixml provision = submodule + own ExternalProject entry (Q1 resolved by orchestrator scope — do NOT use a shaderc-style fetch PATCH_COMMAND for it). (2) D-12 supersedes research SUMMARY fork recommendations — no GNUS forks. (3) The day-one spike (D-11) lands in the FIRST plan, before adapter code, and doubles as the verify step for the json/pugixml config-dir export paths and the `miniocpp::miniocpp` target spelling.
