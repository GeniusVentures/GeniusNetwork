# Phase 1: BlockStore Contract, Memory Backend & Conformance Kit - Pattern Map

**Mapped:** 2026-10-20
**Files analyzed:** 17 new/modified
**Analogs found:** 14 / 17 (3 have no in-codebase analog — macro kit, void_t guard, .gitattributes)

All analog paths verified git-tracked via `git ls-files` inside their owning submodule (`thirdparty`, `thirdparty/AsyncIOManager`, `thirdparty/ipfs-lite-cpp`, `thirdparty/libp2p`, `SuperGenius`). No mirror paths.

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `thirdparty/sgns-blockstore/CMakeLists.txt` | config (build) | — | `thirdparty/AsyncIOManager/CMakeLists.txt` | exact |
| `thirdparty/sgns-blockstore/cmake/functions.cmake` | build utility | — | `thirdparty/AsyncIOManager/cmake/functions.cmake` (`addtest`, lines 8-27) | exact |
| `thirdparty/sgns-blockstore/cmake/config.cmake.in` | config template | — | `thirdparty/AsyncIOManager/cmake/config.cmake.in` (whole file) | exact |
| `thirdparty/sgns-blockstore/src/CMakeLists.txt` | build | — | `thirdparty/AsyncIOManager/CMakeLists.txt:61-77` (`add_subdirectory` + install/export of the lib target) | role-match |
| `thirdparty/sgns-blockstore/include/sgns-blockstore/Cid.hpp` + `src/Cid.cpp` | utility (CID composition) | transform | `thirdparty/ipfs-lite-cpp/primitives/cid/cid.cpp:129-136` (`getCidOf`) | exact-role (deviation: sha-256, not blake2b) |
| `thirdparty/sgns-blockstore/include/sgns-blockstore/BlockStore.hpp` | interface | request-response | `thirdparty/ipfs-lite-cpp/ipfs_lite/ipfs/datastore.hpp:15-58` | exact-role (deviation: delete-free, `PutOutcome` payloads) |
| `thirdparty/sgns-blockstore/include/sgns-blockstore/{BlockStatus,Options,Durability,Capabilities,Block}.hpp` | model (frozen value types) | — | `thirdparty/libp2p/include/libp2p/multi/content_identifier.hpp` (enum class + struct shape) | partial |
| `thirdparty/sgns-blockstore/include/sgns-blockstore/MemoryBlockStore.hpp` + `src/MemoryBlockStore.cpp` | service (reference backend) | key-value CRUD | `thirdparty/ipfs-lite-cpp/ipfs_lite/ipfs/impl/in_memory_datastore.{hpp,cpp}` | exact |
| `thirdparty/sgns-blockstore/test/conformance/BlockStoreConformanceTests.hpp` | test kit (template suite + macro) | — | `thirdparty/ipfs-lite-cpp/test/core/codec/rleplus/rle_plus_codec_test.cpp` (TYPED_TEST) | partial — no one-macro precedent exists |
| `thirdparty/sgns-blockstore/test/conformance/FaultController.hpp` | test seam interface | — | `thirdparty/ipfs-lite-cpp/ipfs_lite/ipfs/datastore.hpp` (pure-virtual + Doxygen style) | role-match |
| `thirdparty/sgns-blockstore/test/cid_spike_test.cpp` | test (C1 spike) | — | `thirdparty/ipfs-lite-cpp/test/core/ipfs_lite/ipfs/in_memory_ipfs_datastore_test.cpp:16-29` | exact-role |
| `thirdparty/sgns-blockstore/test/memory_block_store_test.cpp` | test (backend + kit instantiation) | — | `thirdparty/ipfs-lite-cpp/test/core/ipfs_lite/ipfs/in_memory_ipfs_datastore_test.cpp` | exact |
| `thirdparty/sgns-blockstore/test/api_hygiene_test.cpp` | test (compile-time guard) | — | `thirdparty/libp2p/test/libp2p/security/pnet/psk_test.cpp:38-41` (`static_assert` traits) | role-match (`void_t` probe itself: no analog) |
| `thirdparty/sgns-blockstore/test/CMakeLists.txt` | config (test) | — | `thirdparty/AsyncIOManager/test/src/CMakeLists.txt:19-36` | exact |
| `thirdparty/sgns-blockstore/.gitattributes` | config (line endings) | — | none in sibling submodules | none |
| `thirdparty/build/CommonTargets.cmake` **(modified)** | superbuild orchestration | — | AsyncIOManager entry (~`:741-777`) + wallet-core entry (~`:692-722`) + GTest entry (`:4-12`) | exact |
| `thirdparty/.gitmodules` **(modified)** | config | — | AsyncIOManager row (`:96-98`) | exact |

## Pattern Assignments

### `thirdparty/sgns-blockstore/CMakeLists.txt` (config, build)

**Analog:** `thirdparty/AsyncIOManager/CMakeLists.txt`

**Bootstrap pattern** (lines 1-17):
```cmake
cmake_minimum_required(VERSION 3.20)
# ... (toolchain set() block, lines 2-8 — copy only if the cxx17 toolchain default is wanted)
project(AsyncIOManager LANGUAGES CXX)      # line 12
include(GNUInstallDirs)                    # line 13

set(CMAKE_CXX_STANDARD 17)                 # lines 15-17
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
```

**Test-gate pattern** (lines 52-56) — **DEVIATE on the option name**:
```cmake
option(BUILD_TESTING "Build tests" OFF)     # AsyncIOManager name — DO NOT COPY
if(BUILD_TESTING)
    enable_testing()
    find_package(GTest CONFIG REQUIRED)
endif()
```
Copy the shape, rename the option per the libp2p convention (`thirdparty/libp2p/CMakeLists.txt:23`):
```cmake
option(TESTING "Build tests" ON)   # default ON for standalone dev; superbuild toggles it
```
Reason: `thirdparty/build/CommonCompilerOptions.cmake:100-130` forces `-DBUILD_TESTING:BOOL=OFF` (line ~104) into every ExternalProject via `_CMAKE_COMMON_CACHE_ARGS` — a `BUILD_TESTING`-gated repo can never enable tests through the superbuild.

**Install/export pattern** (lines 72-107):
```cmake
# Install Headers
install(DIRECTORY "${CMAKE_SOURCE_DIR}/include/" DESTINATION "${CMAKE_INSTALL_INCLUDEDIR}" FILES_MATCHING PATTERN "*.h*")

# Install LIB
install(TARGETS AsyncIOManager
    EXPORT AsyncIOManagerTargets DESTINATION "${CMAKE_INSTALL_LIBDIR}")

# Install Targets
set(AsyncIOManager_CONFIG_DESTINATION_DIR "lib/cmake/AsyncIOManager")
install(EXPORT AsyncIOManagerTargets
    FILE AsyncIOManagerTargets.cmake
    DESTINATION ${AsyncIOManager_CONFIG_DESTINATION_DIR}
)

include(CMakePackageConfigHelpers)
configure_package_config_file(${CMAKE_CURRENT_SOURCE_DIR}/cmake/config.cmake.in
    "${CMAKE_CURRENT_BINARY_DIR}/AsyncIOManagerConfig.cmake"
    INSTALL_DESTINATION "lib/cmake/examples"
    NO_SET_AND_CHECK_MACRO
    NO_CHECK_REQUIRED_COMPONENTS_MACRO
)
write_basic_package_version_file(
    "${CMAKE_CURRENT_BINARY_DIR}/AsyncIOManagerConfigVersion.cmake"
    VERSION "${VERSION_STRING}.${SUBVERSION_STRING}"
    COMPATIBILITY AnyNewerVersion
)
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/AsyncIOManagerConfig.cmake
    DESTINATION ${AsyncIOManager_CONFIG_DESTINATION_DIR})
```
Rename `AsyncIOManager`→`sgns-blockstore` throughout; `NAMESPACE sgns-blockstore::` goes on the `install(EXPORT ...)` (AsyncIOManager omits the NAMESPACE — adding it is the improvement the research template prescribes). Dependency block shrinks to `find_package(libp2p CONFIG REQUIRED)` (+ GTest under `TESTING`); every other `find_package` in the analog (Protobuf, MNN, fmt, RocksDB, ...) is dropped.

---

### `thirdparty/sgns-blockstore/cmake/functions.cmake` (build utility)

**Analog:** `thirdparty/AsyncIOManager/cmake/functions.cmake:8-27` — copy `addtest` + `addtest_part` + `disable_clang_tidy` verbatim (drop `compile_proto_to_cpp`):

```cmake
function(addtest test_name)
  add_executable(${test_name} ${ARGN})
  addtest_part(${test_name} ${ARGN})
  target_link_libraries(${test_name}
      GTest::gtest_main
      GTest::gmock_main
      )
  file(MAKE_DIRECTORY ${CMAKE_BINARY_DIR}/xunit)
  set(xml_output "--gtest_output=xml:${CMAKE_BINARY_DIR}/xunit/xunit-${test_name}.xml")
  add_test(
      NAME ${test_name}
      COMMAND $<TARGET_FILE:${test_name}> ${xml_output}
  )
  set_target_properties(${test_name} PROPERTIES
      RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/test_bin
      ARCHIVE_OUTPUT_PATH ${CMAKE_BINARY_DIR}/test_lib
      LIBRARY_OUTPUT_PATH ${CMAKE_BINARY_DIR}/test_lib
      )
  disable_clang_tidy(${test_name})
endfunction()
```

### `thirdparty/sgns-blockstore/cmake/config.cmake.in` (config template)

**Analog:** `thirdparty/AsyncIOManager/cmake/config.cmake.in` (whole file — substitute target name):
```cmake
@PACKAGE_INIT@

include ( "${CMAKE_CURRENT_LIST_DIR}/AsyncIOManagerTargets.cmake" )
```

---

### `include/sgns-blockstore/Cid.hpp` + `src/Cid.cpp` (utility, transform)

**Analog:** `thirdparty/ipfs-lite-cpp/primitives/cid/cid.cpp:129-136` — the repo's existing CID-from-bytes composition:
```cpp
IPFS::outcome::result<CID> getCidOf( gsl::span<const uint8_t> bytes )
{
    auto hash_raw = crypto::blake2b::blake2b_256( bytes );
    BOOST_OUTCOME_TRY( auto hash, Multihash::create( HashType::blake2b_256, hash_raw ) );
    ...
}
```
Declaration style (cid.hpp:87): `IPFS::outcome::result<CID> getCidOf( gsl::span<const uint8_t> bytes );` under a `/// Compute CID from bytes` comment.

**Copy the composition discipline, deviate the hash:** `sgns::blockstore::CidOf(bytes, codec)` uses `libp2p::crypto::sha256` → `Multihash::create(HashType::sha256, ...)` → `ContentIdentifier(Version::V1, codec, mh)` (research Code Examples has the verified body; D-08 rejects non-sha-256 at API entry — document the blake2b CRDT boundary in the header Doxygen).

**The aliased type** (`thirdparty/libp2p/include/libp2p/multi/content_identifier.hpp:21-40`):
```cpp
struct ContentIdentifier
    : public boost::equality_comparable<ContentIdentifier> {
  enum class Version { V0 = 0, V1 = 1 };

  ContentIdentifier(Version version, MulticodecType::Code content_type,
                    Multihash content_address);
  ...
  bool operator==(const ContentIdentifier &c) const;
  bool operator<(const ContentIdentifier &c) const;

  Version version;
  MulticodecType::Code content_type;
  Multihash content_address;
};
```
Key facts the alias inherits: `operator<` exists (line ~38), **no `std::hash`** — see MemoryBlockStore below. The public alias is one line: `using Cid = libp2p::multi::ContentIdentifier;` in `namespace sgns::blockstore` (D-05).

---

### `include/sgns-blockstore/BlockStore.hpp` (interface, request-response)

**Analog:** `thirdparty/ipfs-lite-cpp/ipfs_lite/ipfs/datastore.hpp:15-58` — the codebase's canonical CID-keyed pure-virtual store interface:

```cpp
class IpfsDatastore
{
public:
    using Value = common::Buffer;

    virtual ~IpfsDatastore() = default;

    /**
     * @brief check if data store has value
     * @param key key to find
     * @return true if value exists, false otherwise
     */
    virtual IPFS::outcome::result<bool> contains( const CID &key ) const = 0;

    /**
     * @brief searches for a key in data store
     * @param key key to find
     * @return value associated with key or error
     */
    virtual IPFS::outcome::result<Value> get( const CID &key ) const = 0;
```

Copy: `virtual ~...() = default;`, per-method Doxygen `@brief/@param/@return`, outcome returns, `= 0` pure virtuals, `using` alias for the value type. Deviate:
- **Drop** `remove()`/`seal()`/`is_sealed()` — the analog's `remove` is exactly the delete-shaped method CORE-05 bans (the analog is the counter-example to cite in the guard test comment).
- Miss-as-failure (D-03): `Get` returns `outcome::result<Block, BlockStatus>` — failure slot is the rich `BlockStatus`, not a bare error enum like the analog's `IpfsDatastoreError::NOT_FOUND`.
- `Has(cid) -> outcome::result<bool, BlockStatus>` (never bare `bool`).
- `Put` carries `PutOutcome` (D-04); `PutMany` returns per-block vectors (D-14).
- Restate the eviction invariant in the header doc: "Eviction removes only local cached bytes. It does not delete the object from Sia, remove the path-to-CID mapping, or imply a CRDT deletion." (`supergenius-sharded-ipld-cache-architecture.md:359-361`).

---

### `include/sgns-blockstore/{BlockStatus,Options,Durability,Capabilities,Block}.hpp` (model)

**Analog (shape only):** `thirdparty/libp2p/include/libp2p/multi/content_identifier.hpp` — `enum class Version { V0 = 0, V1 = 1 };` (line ~26) nested-style enum + plain aggregate struct with public members; `@note` doc comment precedent at lines 15-20 (`@note multibase may be omitted...`). Use this shape for `StatusClass`/`BlockSource`/`DurabilityLevel` enums and `BlockStatus`/`PutOutcome`/`ReadOptions`/`WriteOptions` structs. Locked struct shapes come from CONTEXT D-02/D-04/D-15 (verbatim in RESEARCH "Code Examples"), not from any analog.

---

### `include/sgns-blockstore/MemoryBlockStore.hpp` + `src/MemoryBlockStore.cpp` (service, key-value CRUD)

**Analog:** `thirdparty/ipfs-lite-cpp/ipfs_lite/ipfs/impl/in_memory_datastore.hpp` / `.cpp` — exact role match (in-memory CID-keyed map behind a store interface):

Header (hpp:9-31):
```cpp
class InMemoryDatastore : public IpfsDatastore
{
public:
    ~InMemoryDatastore() override = default;

    /** @copydoc IpfsDatastore::contains() */
    IPFS::outcome::result<bool> contains( const CID &key ) const override;

    /** @copydoc IpfsDatastore::get() */
    IPFS::outcome::result<Value> get( const CID &key ) const override;
    ...
private:
    std::map<CID, Value> storage_;      // trailing-underscore member (repo convention)
};
```

Implementation (cpp:8-18, 31-38):
```cpp
IPFS::outcome::result<bool> InMemoryDatastore::contains( const CID &key ) const
{
    return storage_.find( key ) != storage_.end();
}

IPFS::outcome::result<void> InMemoryDatastore::set( const CID &key, Value value )
{
    storage_[key] = value;
    return IPFS::outcome::success();
}

IPFS::outcome::result<Value> InMemoryDatastore::get( const CID &key ) const
{
    BOOST_OUTCOME_TRY( auto found, contains( key ) );
    if ( !found )
    {
        return IpfsDatastoreError::NOT_FOUND;
    }
    return storage_.at( key );
}
```

Copy: `std::map<CID, ...>` keyed by `operator<` (sidesteps the missing `std::hash` — verified pitfall), `/** @copydoc ... */` override docs, trailing-underscore members, miss-as-error return. Deviate: failure returns are `BlockStatus{NotFound, BlockSource::Memory, msg}` structs (D-02) not error enums; **no `remove`** — concrete `EvictLocal(cid)` instead (D-16); `Put` computes and reports `PutOutcome{DurabilityLevel::LocalCommitted, alreadyPresent}`; CID verification runs in the shared facade path with `ReadOptions::verify` toggle (CORE-04).

---

### `test/conformance/BlockStoreConformanceTests.hpp` (test kit)

**Analog (nearest):** `thirdparty/ipfs-lite-cpp/test/core/codec/rleplus/rle_plus_codec_test.cpp:17-33` — the codebase's only parametrized-over-type suite:
```cpp
using types = testing::Types<uint8_t, uint16_t, uint32_t, uint64_t>;

TYPED_TEST_CASE( RLEPlusCodecTester, types );

/**
 * @given Null set of data
 * @when RLE+ encode and following decode back
 * @then Operations must be completed successfully and decoded data must be
 * the same as the given set
 */
TYPED_TEST( RLEPlusCodecTester, NullDataSuccess )
{
    this->checkDataSet( {} );
}
```
Copy the `@given/@when/@then` doc-comment convention and suite-reuse discipline. **No one-macro instantiation precedent exists** — the `SGNS_BLOCKSTORE_CONFORMANCE_TESTS(SuiteName, factory)` macro (D-09) is new shape; use RESEARCH Pattern 2 as the spec. Factory shape precedent from `in_memory_ipfs_datastore_test.cpp:28`:
```cpp
std::shared_ptr<IpfsDatastore> datastore{ std::make_shared<InMemoryDatastore>() };
```
Fault-skip precedent (D-10 "loud labelled skips") — `thirdparty/AsyncIOManager/test/src/ipfs_saver_test.cpp:38-41`:
```cpp
catch ( const std::exception &e )
{
    GTEST_SKIP() << "Cannot create BitswapNode: " << e.what();
}
```
Kit assertions use plain GTest per D-11 (`EXPECT_TRUE(res)` + manual `.value()/.error()` extraction), NOT the repo's outcome macros.

### `test/conformance/FaultController.hpp` (test seam interface)

**Analog (style):** `datastore.hpp:15-28` — minimal pure-virtual class with `virtual ~...() = default;` and Doxygen'd methods. No fault-injection interface exists anywhere in these submodules; the seam shape is D-10 + research. Kit probes via `std::dynamic_pointer_cast<FaultController>(store)`; nullptr → labelled `GTEST_SKIP()` (excerpt above).

---

### `test/cid_spike_test.cpp` (C1 spike)

**Analog:** `thirdparty/ipfs-lite-cpp/test/core/ipfs_lite/ipfs/in_memory_ipfs_datastore_test.cpp:1-29` — CID construction fixtures + literals:
```cpp
#include <gtest/gtest.h>
#include "testutil/literals.hpp"
#include "testutil/outcome.hpp"

using libp2p::multi::HashType;
using libp2p::multi::MulticodecType;
using libp2p::multi::Multihash;
using sgns::CID;

class InMemoryIpfsDatastoreTest : public ::testing::Test
{
public:
    CID cid1{ CID::Version::V1,
              MulticodecType::Code::SHA2_256,
              Multihash::create( HashType::sha256, "0123456789ABCDEF0123456789ABCDEF"_unhex ).value() };
    ...
};
```
Copy the fixture-CID construction pattern (`Multihash::create(...).value()` + `""_unhex` — the new repo needs its own minimal `testutil/literals.hpp` equivalent or inline hex). Spike body = the three verified parts from RESEARCH Code Examples (round-trip, `CidOf` vectors, standalone-TU link assertion with the pre-refined part-3 wording from Pitfall 1).

### `test/memory_block_store_test.cpp` (backend + kit instantiation)

**Analog:** same file — fixture + `TEST_F` + `@given/@when/@then` comments:
```cpp
TEST_F( InMemoryIpfsDatastoreTest, GetNotExistingFailure )
{
    EXPECT_OUTCOME_TRUE_1( datastore->set( cid1, value ) );
    EXPECT_OUTCOME_ERROR( IpfsDatastoreError::NOT_FOUND, datastore->get( cid2 ) );
}
```
`GetNotExistingFailure` (lines 70-75) is the direct template for the kit's miss-conformance case — deviate the assertion to plain GTest per D-11: check `!res`, then `res.error().code == StatusClass::NotFound` and `res.error().source` set. One line instantiates the kit (D-09).

### `test/api_hygiene_test.cpp` (compile-time guard)

**Analog (mechanics):** `thirdparty/libp2p/test/libp2p/security/pnet/psk_test.cpp:38-41` — compile-time API-shape assertions living in a GTest TU:
```cpp
static_assert(!std::is_copy_constructible_v<Psk>);
static_assert(!std::is_copy_assignable_v<Psk>);
static_assert(std::is_move_constructible_v<Psk>);
static_assert(std::is_move_assignable_v<Psk>);
```
Copy the placement pattern (file-scope `static_assert`s inside a test TU that also links the library). **No `void_t` member-detection precedent exists** — use the C++17 SFINAE probe from RESEARCH (`HasEvictLocal<T, void_t<...>>`, banned-name set `Remove/Erase/Delete/erase/remove/List/ForEach/Enumerate` on `BlockStore` all `false_type`; `EvictLocal` true on `MemoryBlockStore` only). Pair with the include-hygiene TU + grep for `ipfs_lite/ipfs/`, `SuperGenius/`, `GeniusSDK/`, `minio`.

### `thirdparty/sgns-blockstore/test/CMakeLists.txt` (config, test)

**Analog:** `thirdparty/AsyncIOManager/test/src/CMakeLists.txt:19-36`:
```cmake
addtest(mnn_loader_test
    mnn_loader_test.cpp
)
target_link_libraries(mnn_loader_test
    spdlog::spdlog
    protobuf::libprotobuf
    AsyncIOManager
    asiomgr_testutil
)
```
Copy `addtest(name sources.cpp)` + immediate `target_link_libraries(name sgns-blockstore p2p::p2p_cid)`; gate the whole dir behind `if(TESTING)` from the root CMakeLists.

---

### `thirdparty/build/CommonTargets.cmake` entry **(modified)** (superbuild orchestration)

**Primary analog:** AsyncIOManager entry (~`:741-777`) — the shape to mirror:
```cmake
# AsyncIOManager
ExternalProject_Add(AsyncIOManager
    PREFIX AsyncIOManager
    SOURCE_DIR "${THIRDPARTY_DIR}/AsyncIOManager"
   CMAKE_CACHE_ARGS
    -DCMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
    -Dlibp2p_DIR:PATH=${_FINDPACKAGE_libp2p_CONFIG_DIR}
    # ... per-dependency *_DIR hints, alphabetized ...
    ${_BOOST_CACHE_ARGS}
    ${_OPENSSL_CACHE_ARGS}
    ${_CMAKE_COMMON_CACHE_ARGS}
    DEPENDS libssh2 openssl ipfs-lite-cpp ipfs-bitswap-cpp protobuf ${PROTOBUF_TARGET} Boost MNN
)
```
The new `sgns-blockstore` entry keeps only `-DGSL_INCLUDE_DIR`, `-DGTest_DIR`, `-Dlibp2p_DIR`, `${_BOOST_CACHE_ARGS}`, `${_OPENSSL_CACHE_ARGS}`, `${_CMAKE_COMMON_CACHE_ARGS}`; `DEPENDS libp2p` only.

**Deviation analogs (wallet-core entry, ~`:692-722`)** — the two things AsyncIOManager's entry lacks:
```cmake
    -DTESTING:BOOL=${TESTING}        # TESTING option name (not BUILD_TESTING); ${TESTING} if
                                     # plumbed from parent, else hard -DTESTING:BOOL=ON placed
                                     # AFTER ${_CMAKE_COMMON_CACHE_ARGS} (they force
                                     # BUILD_TESTING=OFF; later cache args win)
    ...
    DEPENDS Boost protobuf openssl protobuf-plugin
    BUILD_BYPRODUCTS
    "${CMAKE_CURRENT_BINARY_DIR}/wallet-core/lib/libTrustWalletCore.a"
```
`BUILD_BYPRODUCTS` is mandatory for ninja one-pass determinism (AsyncIOManager's omission is a known gap, not a pattern to copy).

**GTest wiring analog** (`:4-12`):
```cmake
ExternalProject_Add(GTest
    PREFIX GTest
    SOURCE_DIR "${THIRDPARTY_DIR}/GTest"
   CMAKE_CACHE_ARGS
    -DCMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
    ${_CMAKE_COMMON_CACHE_ARGS}
)
set(_FINDPACKAGE_GTEST_CONFIG_DIR "${CMAKE_CURRENT_BINARY_DIR}/GTest/lib/cmake/GTest")
```
Pass `-DGTest_DIR:PATH=${_FINDPACKAGE_GTEST_CONFIG_DIR}` into the new entry; after it, set the downstream hint:
`set(_FINDPACKAGE_SGNS_BLOCKSTORE_CONFIG_DIR "${CMAKE_CURRENT_BINARY_DIR}/sgns-blockstore/lib/cmake/sgns-blockstore")`.
(`PATCH_COMMAND` precedent, if ever needed for a pinned dep: shaderc entry, ~`:438`.)

### `thirdparty/.gitmodules` **(modified)** (config)

**Analog:** AsyncIOManager row (`:96-98`):
```ini
[submodule "AsyncIOManager"]
    path = AsyncIOManager
    url = ../AsyncIOManager.git
```
New row: `[submodule "sgns-blockstore"]` / `path = sgns-blockstore` / `url = ../sgns-blockstore.git`. The `git submodule add` itself is execution-time; this map covers only the file edit.

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `test/conformance/BlockStoreConformanceTests.hpp` (macro layer) | test kit | — | No one-macro suite-instantiation precedent in any submodule; nearest is TYPED_TEST (see above). Use RESEARCH Pattern 2 spec verbatim. |
| `test/api_hygiene_test.cpp` (`void_t` probes) | guard test | — | No SFINAE member-detection precedent in-repo; only trait `static_assert`s exist (psk_test.cpp). Use RESEARCH's C++17 SFINAE template. |
| `test/conformance/FaultController.hpp` | test seam | — | No fault-injection interface exists in these submodules; shape is D-10 + datastore.hpp style. |
| `thirdparty/sgns-blockstore/.gitattributes` | config | — | No sibling submodule ships one; create fresh (CRLF hygiene per gsd-windows-crlf memory, Pitfall 5). |

## Shared Patterns

### outcome::result envelope (D-01)
**Source:** `thirdparty/ipfs-lite-cpp/ipfs_lite/ipfs/datastore.hpp:28,47-52` (interface), `in_memory_datastore.cpp:31-38` (implementation with `BOOST_OUTCOME_TRY`)
**Apply to:** every public op on `BlockStore`, `MemoryBlockStore`, `CidOf`.
```cpp
IPFS::outcome::result<Value> get( const CID &key ) const
{
    BOOST_OUTCOME_TRY( auto found, contains( key ) );
    if ( !found ) { return IpfsDatastoreError::NOT_FOUND; }
    return storage_.at( key );
}
```
Repo test macros exist (`SuperGenius/test/testutil/outcome.hpp:33-44` — `EXPECT_OUTCOME_TRUE(val, expr)` / `EXPECT_OUTCOME_FALSE(val, expr)` extracting `.value()`/`.error()`); per D-11 the **kit** uses plain GTest instead, but backend-specific tests and the spike may reuse the macro pattern (self-host a minimal copy — do NOT include SuperGenius headers from the new repo).

### GTest conventions
**Source:** `thirdparty/AsyncIOManager/cmake/functions.cmake:8-27` (`addtest`: `GTest::gtest_main`+`gmock_main`, xunit XML, `test_bin/` output, `disable_clang_tidy`); `in_memory_ipfs_datastore_test.cpp` (`@given/@when/@then` doc comments above every `TEST_F`); `ipfs_saver_test.cpp:38-41` (`GTEST_SKIP() << "label: " << detail` for optional-capability skips).
**Apply to:** all four test TUs + the kit's generated TEST_F bodies. Suite/file naming: `<source>_test.cpp`.

### CMake ExternalProject conventions (superbuild)
**Source:** `thirdparty/build/CommonTargets.cmake:4-12` (GTest), AsyncIOManager entry ~`:741-777`, wallet-core ~`:692-722`; `thirdparty/build/CommonCompilerOptions.cmake:100-130` (`_CMAKE_COMMON_CACHE_ARGS` — includes `-DBUILD_TESTING:BOOL=OFF`, `-DCMAKE_CXX_STANDARD:STRING`, `-DCMAKE_INSTALL_LIBDIR:STRING=lib`, PIC, compiler propagation).
**Apply to:** the new `sgns-blockstore` entry. Invariants: `${_CMAKE_COMMON_CACHE_ARGS}` always last-but-one; explicit `-DTESTING:BOOL=...` after it; `DEPENDS libp2p`; `BUILD_BYPRODUCTS` for the static lib; trailing `set(_FINDPACKAGE_SGNS_BLOCKSTORE_CONFIG_DIR ...)` for future consumers. Repo builds run from `build/<Platform>/<Config>` trees — verification happens there, not in scratch builds (`.planning/codebase/TESTING.md`).

### Doxygen on public interfaces
**Source:** `thirdparty/ipfs-lite-cpp/ipfs_lite/ipfs/datastore.hpp:22-27` (`@brief/@param/@return` per method); `thirdparty/libp2p/include/libp2p/multi/content_identifier.hpp:12-20` (`@note` for contract caveats); `in_memory_datastore.hpp:14` (`/** @copydoc IfsDatastore::contains() */` for overrides).
**Apply to:** all seven public headers. The `BlockStore.hpp` class doc carries the eviction-invariant quote and the sha-256-only hashing boundary (D-08 / Pitfall 3).

### C++ style (Coding Standards.md)
**Apply to:** every header/TU: namespace `sgns::blockstore`; PascalCase types, headers, methods (`Put`, `GetSize`, `IsNameEmpty`-style bools); trailing-underscore members (`storage_` — `in_memory_datastore.hpp:29`); Ullman braces on their own lines; `gsl::span<const uint8_t>` for buffer params (cid.hpp:87 precedent); `enum class` with explicit values where wire-stable (`Version { V0 = 0, V1 = 1 }` precedent); include guards `SUPERGENIUS_..._HPP`-shaped (adapt: `SGNS_BLOCKSTORE_..._HPP`).

## Metadata

**Analog search scope:** `thirdparty/AsyncIOManager/**`, `thirdparty/ipfs-lite-cpp/{ipfs_lite,primitives,test}/**`, `thirdparty/libp2p/{include,test,CMakeLists.txt}`, `thirdparty/build/{CommonTargets.cmake,CommonCompilerOptions.cmake}`, `thirdparty/.gitmodules`, `SuperGenius/test/testutil/`, `.planning/codebase/TESTING.md`
**Tracked-source gate:** all named analogs verified via `git ls-files` inside their owning (nested) submodules — no gitignored/mirror paths emitted
**Files scanned:** ~20 read in targeted ranges; searches: in-memory store, TYPED_TEST, static_assert/void_t, getCidOf, option(TESTING), .gitattributes
**Pattern extraction date:** 2026-10-20
