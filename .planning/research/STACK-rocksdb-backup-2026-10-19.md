# Stack Research

**Domain:** CID-native cold-storage C++ library (`sgns-blockstore`) — BlockStore abstraction + RocksDB local + S3 (MinIO SDK / Sia s3d) durable backends
**Researched:** 2026-10-19
**Confidence:** HIGH (versions verified against upstream repos 2026-10-19; integration details verified against `thirdparty/build/` sources in this workspace)

**Scope guard:** this covers ONLY what is NEW for the `sgns-blockstore` library (doc Phase 1+2 vertical slice). Existing thirdparty stack (Boost ~1.85/1.89, libp2p, ipfs-lite-cpp, RocksDB, OpenSSL ~3.0, GTest ~1.14, protobuf, spdlog/soralog, CMake/C++17 conventions) is assumed and not re-researched. Out of scope this milestone: tiered retrieval, path sharding, eviction policy, CARv2, PeerBlockStore.

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| `sgns-blockstore` (new GNUS static lib) | 0.1.0 | The library itself: `BlockStore` interface + `MemoryBlockStore` + `LocalBlockStore` (RocksDB) + `S3BlockStore` behind an internal `S3Client` adapter | Modeled on existing GNUS-authored thirdparty libs (`AsyncIOManager`, `gnus_upnp`): C++17, `find_package(... CONFIG)` everywhere, installs `lib/cmake/sgns-blockstore/` export so both SuperGenius/GeniusSDK and genius-tube consume it identically without SuperGenius headers |
| **minio/minio-cpp** (MinIO C++ SDK) | **v1.0.0** (2026-09-09) | S3 client used by the `MinioS3Client` adapter implementation (PutObject/GetObject/HeadObject/DeleteObject, SigV4, path-style, multipart, checksums) | See detailed assessment below — C++17 floor, Apache-2.0, actively maintained (4 releases Aug–Sep 2026, led by MinIO founder), dependency set is tiny and mostly already in thirdparty, first-class static builds, MSVC/Clang/GCC support. Matches the architecture doc's existing recommendation ("C++ S3 client recommendation" section) |
| **libp2p `p2p_cid`** (existing `thirdparty/libp2p`) | current submodule pin | CID type for the public API: `libp2p::multi::ContentIdentifier` + `ContentIdentifierCodec` (parse/format CIDv0/v1) + `p2p_multihash`/`p2p_sha` (OpenSSL SHA-256) for CID verification | Already built on all 5 platforms by `CommonTargets.cmake`; Apache-2.0; zero SuperGenius coupling; the narrowest complete CID implementation we own. `p2p_cid` links only `p2p_multihash`, `p2p_sha`, `p2p_uvarint`, `p2p_multibase_codec` (`thirdparty/libp2p/src/multi/CMakeLists.txt`) — no networking stack needed |
| **RocksDB** (existing, consumer-provided) | 9.4.0 in this checkout; genius-tube pins 11.1.2 | Local durable backend (`LocalBlockStore`) via `find_package(RocksDB CONFIG REQUIRED)` | Already integrated; genius-tube mandate (RocksDB built from thirdparty/, column families separating hot indexes from cold blobs) is satisfied by consuming the consumer's RocksDB rather than bundling one. Library must stick to the stable `rocksdb::*` API surface common to 9.x–11.x and declare minimum 9.4 |

### Detailed assessment: MinIO C++ SDK (minio/minio-cpp) — the headline addition

Verified against `github.com/minio/minio-cpp` and `github.com/minio/minio-cpp/releases` on 2026-10-19:

- **Current version: v1.0.0**, released 2026-09-09 ("build: release 1.0.0 as libminio, with a stable soname", #264). Release history: v0.4.0 (2026-05-27) → v0.5.0 (2026-08-15) → v0.6.0 (2026-08-16) → v0.7.0 (2026-08-22) → **v1.0.0 (2026-09-09)**. Last commit ~1 month before this research (Sep 2026).
- **Maintenance status: ACTIVE.** Driven by `harshavardhana` (MinIO founder/CTO) + `balamurugana` (long-time minio-cpp maintainer); 25 contributors; recent substantive work (Windows large-file/binary-safe downloads #248, cpp-httplib migration #257, Alpine/musl support #255, static link-line fix #265). Notable: the *client SDK* repo is healthy and independent of the *MinIO server* repo's archival (see Test Infrastructure below).
- **C++17 compatibility: exact match.** README build requirements: "A working C++ compiler that supports at least C++17." C++20 is opt-in (`-DMINIO_CPP_STD=20` unlocks span/format/coroutines; C++17 users get `tl::expected` shims). GNUS thirdparty pins `CMAKE_CXX_STANDARD 17` in `CommonCompilerOptions.cmake` — no conflict.
- **Dependencies (v1.0.0, from `vcpkg.json` + `cmake/miniocpp-deps.cmake`)** — important: the dependency set CHANGED in v0.7.0. It is **no longer curl/curlpp-based**:
  - `cpp-httplib` (with OpenSSL feature) — HTTP/TLS transport (replaced curlpp in #257, Aug 2026). minio-cpp's own source-fallback pins v0.53.1; upstream latest is **v0.62.0** (2026-10-18).
  - `inih` (C lib + `INIReader` C++ wrapper)
  - `nlohmann-json` — **already in thirdparty** (`json` submodule, pinned v3.12.0, installs a config package)
  - `openssl` — already in thirdparty (~3.0)
  - `pugixml` — XML parsing for S3 responses (replaces libxml; minio-cpp never needed libxml2 in current line)
  - `zlib` — already in thirdparty (needed on Windows)
  - Exact link order (deps file): `httplib, inih, nlohmann_json, pugixml, OpenSSL::SSL, OpenSSL::Crypto, ZLIB::ZLIB`.
- **CMake targets/consumption:** `find_package(miniocpp REQUIRED)` → link `miniocpp::miniocpp`; headers under `#include <miniocpp/...>`. The v1.0.0 shared-library rename to `libminio` (soname `libminio.so.1`) does NOT change the CMake package name, exported target, or include dir — and is irrelevant to us anyway because we build static.
- **Static-build feasibility: first-class.** Upstream ships *prebuilt fully-static bundles* (lib + ALL deps + CMake configs) for linux-amd64/arm64, macos-amd64/arm64, windows-amd64; `miniocpp.pc` carries a complete static link line (#265). Plain `BUILD_SHARED_LIBS=OFF` source builds are the supported path in our `_CMAKE_COMMON_CACHE_ARGS` model.
- **Platform support:** MSVC (Windows prebuilts + dedicated Windows fixes), GCC (Linux x86_64/arm64, Alpine/musl), Clang (macOS amd64/arm64). Android/iOS: not covered by prebuilts, but every dependency (cpp-httplib, pugixml, inih, OpenSSL, zlib) cross-compiles cleanly with no build-time host tools, so source builds follow the standard thirdparty cross-compile path.
- **Licensing:** Apache-2.0 for the SDK. Exception: vendored `libs3rdma` RDMA binaries under `vendor/s3rdma/` are MinIO-proprietary — **keep `-DMINIO_CPP_ENABLE_RDMA=OFF` (the default)** and this never enters the build.
- **One hermeticity hazard:** `cmake/miniocpp-deps.cmake` resolves each dependency as *vcpkg config → pkg-config → git clone from upstream at configure time* (that's the musl fallback). A configure-time `git clone` is unacceptable inside our ExternalProject builds, and **pugixml missing = hard `FATAL_ERROR`**. Mitigation in Integration section below (pre-provide config packages; patch the fallback in a GNUS fork, following the existing boost-patch precedent).

### minio-cpp vs AWS SDK for C++ (for a minimal S3 client behind a small adapter)

| Criterion | minio-cpp v1.0.0 | aws-sdk-cpp 1.11.913 (latest, 2026-10) |
|-----------|------------------|------------------------------------------|
| C++ standard | C++17 (opt-in C++20) | C++11 |
| External deps to add to thirdparty | pugixml, cpp-httplib, inih (tiny) — openssl/zlib/nlohmann-json already present | **libcurl (not in thirdparty today)** + aws-crt-cpp stack (aws-c-common, aws-c-event-stream, aws-checksums, s2n) built from the `crt/` submodule |
| Build weight even for "S3 only" | One small library, handful of TUs | `-DBUILD_ONLY=s3` still builds core + s3 + CRT; README warns 4 GB RAM and long builds |
| Maintenance (verified Oct 2026) | Active, human-driven, small surface | Active, daily machine-generated releases; huge generated surface |
| Mobile (iOS/Android cross-compile) | Clean (no host tools, simple deps) | Possible but documented against NDK 19c / APIs 19–28 (dated); CRT adds cross-compile friction |
| Fit behind `S3Client` adapter | Ideal: 4 calls we need (Put/Get/Head/Delete) are direct | Overkill; would add ~6 new thirdparty targets incl. curl |

**Recommendation: minio-cpp.** The architecture doc already isolates the SDK behind the internal `S3Client` interface precisely so this choice stays reversible; AWS SDK only becomes interesting if AWS-native features (CRT transfer manager, SigV4A, other services) are ever required — none are in this slice.

### CID source decision

| Option | Verdict | Reason |
|--------|---------|--------|
| **libp2p `p2p_cid` (recommended)** | ✅ Use | Complete (CIDv0/v1 parse/format/bytes ↔ string via `ContentIdentifierCodec`), already built on all platforms, smallest footprint (`p2p_cid` → multihash + sha(OpenSSL) + uvarint + multibase), Apache-2.0, no SuperGenius symbols. Public API of `sgns-blockstore` uses `libp2p::multi::ContentIdentifier` directly |
| ipfs-lite-cpp `sgns::CID` | ❌ Don't | It's only a thin subclass of `ContentIdentifier` (default ctor + CBOR conveniences — see `thirdparty/ipfs-lite-cpp/primitives/cid/cid.hpp`), but its `cid` CMake target links `fmt`, `soralog`, `c-ares`, `blake2`, `cbor` and drags the whole ipfs-lite-cpp package. Genius-tube must not need ipfs-lite-cpp just to get a CID type |
| Self-contained CID lib | ❌ Don't | Duplicates domain knowledge already owned by libp2p (varint, multihash, multibase base32/base58, multicodec tables); hand-rolling these is exactly the class of subtle bug CID verification exists to catch |

### Supporting Libraries (all NEW thirdparty additions)

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| **pugixml** (github.com/zeux/pugixml) | **v1.16** (2026-06-16) | XML parsing inside minio-cpp (S3 List/Error responses) | Required by minio-cpp; hard `FATAL_ERROR` in its deps resolver if absent. CMake-native, 3 source files, installs `pugixml` config package, MSVC/Clang/GCC, trivially cross-compiles |
| **cpp-httplib** (github.com/yhirose/cpp-httplib) | **v0.62.0** (2026-10-18) | Header-only HTTP/HTTPS client used by minio-cpp (OpenSSL backend) | Required by minio-cpp v0.7.0+. CMake install exports `httplib` target with `HTTPLIB_IS_USING_OPENSSL` etc. Pin ≥ v0.53.1 (minio-cpp's minimum); v0.62.0 is current and very active (security-hardened line through 2026) |
| **inih** (github.com/benhoyt/inih) | **r62** (2025-09-11) | INI parsing (credential/config files) inside minio-cpp, via the `INIReader` C++ wrapper | Required by minio-cpp. Caveat: upstream is **meson-only** (no CMakeLists) — see Integration for the fork/wrapper strategy |

No new supporting libs beyond these three: nlohmann-json (`json` @ v3.12.0), OpenSSL, zlib, RocksDB, libp2p, GTest all exist in thirdparty today.

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| Docker + **`minio/minio:RELEASE.2025-10-15T17-29-55Z`** (also on quay.io) | Hermetic CI S3 endpoint for `S3BlockStore` tests | minio/minio repo was **archived 2026-04-25**; community server is now source-only and prebuilt images are frozen — a *frozen tag is a feature* for deterministic test fixtures. Pin tag (or digest). Test-only AGPL usage is fine; never expose the container |
| **Sia `s3d`** v0.2.1 (ghcr.io/siafoundation/s3d, or native binary) | Acceptance-test backend: durable Sia roundtrip | Active (7 releases, latest ~2026-10-05, commits weekly). NOT hermetic: `s3d login` needs a Sia account/recovery phrase + indexer registration and uploads hit the real Sia network — so it's a gated/manual acceptance target, not CI. Default config paths documented for Linux, macOS, and Windows (`%APPDATA%/s3d`) → cross-platform binaries exist; Docker image is the primary ops form |
| GTest ~1.14 (existing) | Unit/integration test framework | Follow the repo pattern: tests inside `sgns-blockstore/test/`, built behind `BUILD_TESTING`/`TESTING` cache arg (as `AsyncIOManager` does), S3 tests skip gracefully when no endpoint env var is set |

## Installation (integration into the existing thirdparty orchestration)

No package manager involved — everything is submodules + `ExternalProject_Add`, per `thirdparty/AGENTS.md`. Concrete changes:

### 1. New submodules (`.gitmodules` + `git submodule add`)

```
thirdparty/pugixml        @ v1.16        (upstream zeux/pugixml)
thirdparty/cpp-httplib    @ v0.62.0      (upstream yhirose/cpp-httplib)
thirdparty/inih           @ r62          (GNUS fork of benhoyt/inih adding a minimal CMakeLists — upstream is meson-only)
thirdparty/minio-cpp      @ v1.0.0       (GNUS fork of minio/minio-cpp pinned at v1.0.0 with a small patch to cmake/miniocpp-deps.cmake — see step 3)
thirdparty/sgns-blockstore@ v0.1.0       (new GeniusVentures repo, like AsyncIOManager/gnus_upnp)
```

Fork-with-patch is established practice here: `thirdparty/build/Windows/CMakeLists.txt` already applies `boost_patch_185.diff` to the boost submodule at build time.

### 2. Files that change

| File | Change |
|------|--------|
| `thirdparty/build/CommonTargets.cmake` | Add 5 `ExternalProject_Add` blocks (pugixml, cpp-httplib, inih, minio-cpp, sgns-blockstore) in dependency order, each with `set(_FINDPACKAGE_<NAME>_CONFIG_DIR ...)` exports, `${_CMAKE_COMMON_CACHE_ARGS}` (static/PIC/pinned `lib` libdir/compiler propagation — `CommonCompilerOptions.cmake:100`), `${_OPENSSL_CACHE_ARGS}`, `${_ZLIB_PACKAGE_ARGS}`, `DEPENDS`, and `BUILD_BYPRODUCTS` (ninja one-pass determinism; see the two-ninja-runs gotcha in `CMAKE_ANALYSIS_README.md`) |
| `thirdparty/build/{Windows,Linux,OSX,iOS,Android}/CMakeLists.txt` | **No change required** — each platform file already `include(../CommonTargets.cmake)` (verified: `Windows/CMakeLists.txt:125`). Only add per-platform overrides if something surfaces (pattern: `_rocksdb_EXTRA_PARAM`-style variables) |
| `thirdparty/sgns-blockstore/CMakeLists.txt` (new repo) | Copy the `AsyncIOManager/CMakeLists.txt` shape: `CMAKE_CXX_STANDARD 17`, `find_package(RocksDB/libp2p/miniocpp CONFIG REQUIRED)`, GTest behind `BUILD_TESTING`, `install(TARGETS ... EXPORT sgns-blockstoreTargets)` + `configure_package_config_file` + `write_basic_package_version_file` → `lib/cmake/sgns-blockstore/` |
| Consumer builds (SuperGenius/GeniusSDK/genius-tube) | **Later milestones only**: pass `-Dsgns-blockstore_DIR=<thirdparty-build>/sgns-blockstore/lib/cmake/sgns-blockstore` (and `-Dminiocpp_DIR=...` transitively) exactly as ipfs-lite-cpp consumers do today (`CommonTargets.cmake:545` pattern) |

### 3. minio-cpp ExternalProject sketch (the one non-obvious wiring)

```cmake
# pugixml / cpp-httplib / inih first, each exporting its config dir, then:

ExternalProject_Add(minio-cpp
    PREFIX minio-cpp
    SOURCE_DIR "${THIRDPARTY_DIR}/minio-cpp"
    CMAKE_CACHE_ARGS
    -DCMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
    -Dpugixml_DIR:PATH=${_FINDPACKAGE_PUGIXML_CONFIG_DIR}
    -Dhttplib_DIR:PATH=${_FINDPACKAGE_HTTPLIB_CONFIG_DIR}
    -Dinih_DIR:PATH=${_FINDPACKAGE_INIH_CONFIG_DIR}      # provided by GNUS inih fork
    -Dnlohmann_json_DIR:PATH=${_FINDPACKAGE_JSON_CONFIG_DIR}
    -DMINIO_CPP_ENABLE_RDMA:BOOL=OFF
    -DMINIO_CPP_TEST:BOOL=OFF
    ${_ZLIB_PACKAGE_ARGS}
    ${_OPENSSL_CACHE_ARGS}
    ${_CMAKE_COMMON_CACHE_ARGS}                          # static, PIC, lib/, compilers
    BUILD_BYPRODUCTS "${CMAKE_CURRENT_BINARY_DIR}/minio-cpp/lib/libminio.a"
    DEPENDS pugixml cpp-httplib inih
)
set(_FINDPACKAGE_MINIOCPP_CONFIG_DIR "${CMAKE_CURRENT_BINARY_DIR}/minio-cpp/lib/cmake/miniocpp")

ExternalProject_Add(sgns-blockstore
    PREFIX sgns-blockstore
    SOURCE_DIR "${THIRDPARTY_DIR}/sgns-blockstore"
    CMAKE_CACHE_ARGS
    -DCMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
    -Dlibp2p_DIR:PATH=${_FINDPACKAGE_libp2p_CONFIG_DIR}
    -Dminiocpp_DIR:PATH=${_FINDPACKAGE_MINIOCPP_CONFIG_DIR}
    -DRocksDB_DIR:PATH=${_FINDPACKAGE_ROCKSDB_DIR}
    -DGTest_DIR:PATH=${_FINDPACKAGE_GTEST_CONFIG_DIR}
    -DTESTING:BOOL=${TESTING}
    ${_CMAKE_COMMON_CACHE_ARGS}
    DEPENDS rocksdb libp2p minio-cpp
    BUILD_BYPRODUCTS "${CMAKE_CURRENT_BINARY_DIR}/sgns-blockstore/lib/libsgns-blockstore.a"
)
```

The GNUS-fork patch to `minio-cpp/cmake/miniocpp-deps.cmake` should do two things: (a) accept pre-provided config packages for cpp-httplib/inih before any vcpkg/pkg-config probing, and (b) turn the configure-time `git clone` fallback into a hard error. This keeps builds hermetic and offline-safe. With all five config packages present the fallback never triggers even unpatched — the patch is defense-in-depth.

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| minio-cpp v1.0.0 | AWS SDK for C++ (`BUILD_ONLY=s3`) | Only if AWS-native features become requirements (CRT transfer manager, SigV4A, non-S3 services). Cost: libcurl + CRT stack (~6 new thirdparty targets), heavy build |
| minio-cpp v1.0.0 | Apache OpenDAL C++ binding | Not yet — architecture doc already flags it as "future possibility" only if it becomes production-ready |
| minio-cpp v1.0.0 | Hand-rolled SigV4 client on Boost.Beast | Never for this slice: SigV4/chunked-signing/XML error handling is high-risk duplicated domain knowledge; the `S3Client` adapter keeps the door open if we ever must |
| libp2p `p2p_cid` | ipfs-lite-cpp `sgns::CID` | Only if a consumer already mandates ipfs-lite-cpp in the same binary AND wants CBOR codec interop for free — still prefer consuming the libp2p base type at the API boundary |
| Pinned frozen MinIO image for CI | SeaweedFS (Apache-2.0, active) as CI S3 endpoint | If the frozen image ever becomes a real problem (CVE exposure in CI, architecture mismatch) — today determinism beats freshness for a test fixture |
| GNUS fork of inih + CMakeLists | Building inih via meson in ExternalProject | If the team prefers zero forks over zero extra host tools; meson adds a host dependency across all platforms — the fork is cheaper |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| libcurl / aws-sdk-cpp | Not in thirdparty today; curl static-on-Windows is a known tar pit; would only be needed by the AWS SDK path | cpp-httplib (comes with minio-cpp, header-only, OpenSSL backend) |
| libxml2 | Not needed by any recommended component (minio-cpp uses pugixml) | pugixml v1.16 |
| A bundled/private RocksDB inside sgns-blockstore | genius-tube mandates RocksDB 11.1.2 from thirdparty; this workspace's thirdparty/rocksdb is 9.4.0 (`include/rocksdb/version.h`). Two RocksDBs in one process is unsupported | `find_package(RocksDB CONFIG REQUIRED)` — consumer-provided, stable-API-only |
| ipfs-lite-cpp as a dependency of sgns-blockstore | Defeats "consumable by genius-tube without SuperGenius-adjacent baggage"; drags fmt/soralog/c-ares/cbor for a CID type | libp2p `p2p_cid` |
| sqlite3 for block metadata | Duplicates the local-store role; RocksDB is already the local durable layer | RocksDB (column families for hot index vs cold blob, per genius-tube convention) |
| Async runtime coupling (Boost.Asio coroutine interfaces) in the public API | Locks every consumer into our executor choice; Phase 1+2 needs none of it | Synchronous `BlockStore` interface (per architecture doc); callers wrap in their own executor |
| minio-cpp RDMA / `vendor/s3rdma` | Non-Apache license; AIStor-only feature; irrelevant to s3d/MinIO-test targets | Keep `MINIO_CPP_ENABLE_RDMA=OFF` |
| s3d in CI | Requires Sia account, indexer registration, real uploads (cost/funding) — not hermetic | Pinned MinIO image for CI; s3d as gated acceptance target |

## Stack Patterns by Variant

**If the consumer is genius-tube (no SuperGenius in tree):**
- Static `libsgns-blockstore.a` + `p2p_cid` + `miniocpp` + its three small deps resolve entirely from genius-tube's own thirdparty; nothing references SuperGenius headers.
- RocksDB arrives from genius-tube's thirdparty @ 11.1.2 — library code must compile against both 9.4.0 and 11.1.2 (stable `rocksdb::DB`/`Options`/`ColumnFamilyHandle` API only; no 10.x/11.x-only APIs without a version guard).

**If the platform is iOS/Android:**
- Everything still builds (no host tools run during any of these builds — unlike protobuf, no host/target split is needed). If mobile link weight ever matters, add a `SGNS_BLOCKSTORE_BUILD_S3` CMake option that compiles out the S3 backend; default ON everywhere for uniformity. Decide via measurement, not anticipation (YAGNI).

**If CI has no Docker:**
- S3 integration tests skip via env-var guard (`SGNS_BLOCKSTORE_TEST_S3_ENDPOINT` unset → GTEST_SKIP), keeping unit suites hermetic; the MinIO-backed suite runs only in CI lanes with service containers.

**If TLS is required against s3d:**
- s3d's built-in HTTPS uses a regenerated self-signed cert for localhost — client must skip verification (`BaseUrl` cert settings) or sit behind a reverse proxy; prefer plain HTTP on the loopback/ops network for the first slice, TLS verify via real certificates later.

## Version Compatibility

| Component | Requires | Notes |
|-----------|----------|-------|
| minio-cpp v1.0.0 | CMake ≥ 3.13.4; C++17 | `_CMAKE_COMMON_CACHE_ARGS` propagates our C++17 and compilers; config package `miniocpp`, target `miniocpp::miniocpp` |
| minio-cpp v1.0.0 ↔ cpp-httplib | ≥ v0.53.1 (minio-cpp's pinned minimum); recommend v0.62.0 | Any ≥ 0.53.1 works; vcpkg port tracks recent releases, so v0.62.0 matches what upstream tests against |
| minio-cpp v1.0.0 ↔ OpenSSL | thirdparty OpenSSL ~3.0 | cpp-httplib OpenSSL backend + SigV4 HMAC via `OpenSSL::Crypto` |
| minio-cpp v1.0.0 ↔ nlohmann/json | thirdparty `json` v3.12.0 | Config package already installed by the `json` ExternalProject |
| sgns-blockstore ↔ RocksDB | min 9.4.0 (this workspace); tested by genius-tube at 11.1.2 | Stable C++ API only; no private bundling |
| sgns-blockstore ↔ libp2p | current thirdparty pin | Only `p2p_cid` corner (`ContentIdentifier`, `ContentIdentifierCodec`, `Multihash`, OpenSSL sha) |
| pugixml v1.16 / inih r62 | C++17/C99, any CMake ≥ 3.13 | pugixml adds VS2026 project compat; inih needs GNUS CMakeLists fork |
| s3d v0.2.1 ↔ minio-cpp client | AWS SigV4, path-style addressing, multipart (5 MiB–5 GiB parts, ≤10k parts), conditional `If-None-Match` on PutObject | All within minio-cpp's feature set; conditional writes available for idempotent PUTs |

## Research Flags for the Planner

1. **RocksDB version skew (9.4.0 here vs 11.1.2 genius-tube)** — decision needed: keep dual-compatible API surface (recommended, cheap for the Phase 1+2 slice) vs bump this workspace's thirdparty/rocksdb (out of scope, touches every consumer).
2. **inih integration shape** — GNUS fork with CMakeLists vs meson-in-ExternalProject; recommend fork, but the fork repo must exist before the thirdparty build task runs.
3. **minio-cpp hermeticity patch** — small but must land in the GNUS fork before CI; otherwise the first offline build may attempt configure-time `git clone`.
4. **s3d acceptance harness** — needs an ops story (Sia account, funded wallet, credentials) that is NOT a CI dependency; plan it as a documented manual/tagged test.

## Sources

- github.com/minio/minio-cpp (README, releases v1.0.0…v0.4.0, `vcpkg.json`, `cmake/miniocpp-deps.cmake`) — fetched 2026-10-19, **HIGH** (primary upstream)
- github.com/aws/aws-sdk-cpp (README, releases 1.11.913, CRT submodule) — fetched 2026-10-19, **HIGH** (primary upstream)
- github.com/yhirose/cpp-httplib/releases (v0.62.0 … v0.54.1) — fetched 2026-10-19, **HIGH**
- github.com/zeux/pugixml/releases (v1.16, v1.15) — fetched 2026-10-19, **HIGH**
- github.com/benhoyt/inih/releases (r62 … r53) — fetched 2026-10-19, **HIGH**
- github.com/SiaFoundation/s3d (README: overview, compatibility matrix, upload packing, config paths, Docker, admin API; releases v0.2.1) — fetched 2026-10-19, **HIGH**
- github.com/minio/minio (archival notice 2026-04-25, source-only distribution policy, legacy release freeze) — fetched 2026-10-19, **HIGH**
- Workspace sources (authoritative for integration): `thirdparty/build/CommonTargets.cmake`, `thirdparty/build/CommonCompilerOptions.cmake`, `thirdparty/build/Windows/CMakeLists.txt`, `thirdparty/AGENTS.md`, `thirdparty/AsyncIOManager/CMakeLists.txt`, `thirdparty/libp2p/src/multi/CMakeLists.txt`, `thirdparty/libp2p/src/crypto/sha/sha256.cpp`, `thirdparty/ipfs-lite-cpp/primitives/cid/{cid.hpp,CMakeLists.txt}`, `thirdparty/rocksdb/include/rocksdb/version.h`, `supergenius-sharded-ipld-cache-architecture.md` — read 2026-10-19, **HIGH**
