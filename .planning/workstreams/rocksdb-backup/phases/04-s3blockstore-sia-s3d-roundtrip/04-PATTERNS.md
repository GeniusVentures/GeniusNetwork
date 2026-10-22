# Phase 4: S3BlockStore & Sia s3d Roundtrip - Pattern Map

**Mapped:** 2026-10-21
**Files analyzed:** 19 (12 created/moved, 7 modified)
**Analogs found:** 16 exact/role-match + 2 partial / 19 total (1 with no analog)

All analog paths verified **git-tracked** (`git ls-files` in `thirdparty/sgns-blockstore` on `main`, in the outer repo for `.planning/` artifacts, and in the `thirdparty` repo for `build/CommonTargets.cmake`). No gitignored mirror paths are named.

**Correction to 04-RESEARCH.md (verified this session):** the `add_library(sgns-blockstore ...)` source list lives in `thirdparty/sgns-blockstore/src/CMakeLists.txt:1-7` — NOT in `thirdparty/build/CommonTargets.cmake`. `CommonTargets.cmake:863-919` is only the `ExternalProject_Add(sgns-blockstore ...)` wrapper and needs **no changes** this phase (no new `DEPENDS`, no new entries). New sources (`S3BlockStore.cpp`, `UploadDrainer.cpp`) are added to `src/CMakeLists.txt`.

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `include/sgns-blockstore/S3BlockStore.hpp` | store backend header (installed) | request-response | `include/sgns-blockstore/MemoryBlockStore.hpp` | exact |
| `src/S3BlockStore.cpp` | store backend impl | request-response | `src/MemoryBlockStore.cpp` + `src/MinioS3Client.cpp` (mapper discipline) | exact |
| `include/sgns-blockstore/UploadDrainer.hpp` | orchestration utility (installed API) | batch | `include/sgns-blockstore/BlockStoreTooling.hpp` (installed non-data-path surface) | role-match |
| `src/UploadDrainer.cpp` | orchestration impl | batch | `src/MemoryBlockStore.cpp` (`PutMany` per-item loop) + `src/LocalBlockStore.cpp` (`TransitionJournal`) | role-match |
| `include/sgns-blockstore/S3Client.hpp` (git mv from `src/S3Client.hpp`) | provider interface header (installed) | request-response | itself; move mechanics: `CMakeLists.txt:52-54` install rule | exact (move) |
| `test/s3_block_store_test.cpp` | test (conformance + key layout) | CRUD/conformance | `test/memory_block_store_test.cpp:381-392` | exact |
| `test/upload_drainer_test.cpp` | test (journal-advance assertions) | batch | `test/local_block_store_test.cpp:336-375` | exact |
| `test/s3_block_store_minio_test.cpp` | env-gated integration test (opt-in MinIO tier) | request-response | `test/minio_cpp_spike_test.cpp:252-310` + `test/CMakeLists.txt` minio entries | exact |
| `test/s3d_spike_test.cpp` (shape at planner discretion) | dev-gated live spike test | request-response | `test/minio_cpp_spike_test.cpp` | exact |
| `test/s3d_roundtrip_e2e.cpp` | dev-gated two-run E2E binary | request-response (two fresh processes) | env-gate: `test/minio_cpp_spike_test.cpp:264-267`; two-run mechanics: NO in-repo analog | partial |
| `test/CMakeLists.txt` (modified) | build config | — | itself (existing `addtest()` entries) | exact |
| `test/api_hygiene_test.cpp` (modified) | API-shape guard test | — | itself (`test/api_hygiene_test.cpp:38-48,166-190`) | exact |
| `src/InMemoryS3Client.hpp/.cpp` (modified) | test fake (include swap) | CRUD | itself (include line 20) | exact |
| `src/MinioS3Client.hpp` (modified) | adapter impl header (include swap) | request-response | itself | exact |
| `src/CMakeLists.txt` (modified) | build config | — | itself (`src/CMakeLists.txt:1-7`) | exact |
| `include/sgns-blockstore/Durability.hpp` (modified) | model header (doc citation D-12) | — | itself (`Durability.hpp:29-44`) | exact |
| `docs/s3d-durability.md` | documentation (characterization) | — | none (repo has no `docs/`, no README) | none |
| `docs/evidence/s3d-spike/*` | evidence artifacts | — | `03-04-live-run-evidence.log` (evidence discipline) | role-match |
| `.planning/.../04-s3blockstore-sia-s3d-roundtrip/04-XX-live-run-evidence.log` | committed run log | — | `03-04-live-run-evidence.log` | exact |

**Explicitly NOT modified:** `thirdparty/build/CommonTargets.cmake` — library-internal phase; the ExternalProject entry stays untouched (verified this session).

## Pattern Assignments

### `include/sgns-blockstore/S3BlockStore.hpp` + `src/S3BlockStore.cpp` (store backend, request-response)

**Analog:** `include/sgns-blockstore/MemoryBlockStore.hpp` (header) / `src/MemoryBlockStore.cpp` (impl); mapper discipline from `src/MinioS3Client.cpp`.

**Header skeleton** — copy `MemoryBlockStore.hpp` verbatim structure: `@file/@brief` Doxygen banner, `SGNS_BLOCKSTORE_<NAME>_HPP` guard, `<sgns-blockstore/...>` includes, class with `@copydoc BlockStore::X()` overrides, documented thread-safety `@note`:

```cpp
// Source: thirdparty/sgns-blockstore/include/sgns-blockstore/MemoryBlockStore.hpp:1-44
/**
 * @file MemoryBlockStore.hpp
 * @brief The hermetic in-memory reference backend (BACK-01).
 */
#ifndef SGNS_BLOCKSTORE_MEMORYBLOCKSTORE_HPP
#define SGNS_BLOCKSTORE_MEMORYBLOCKSTORE_HPP
...
namespace sgns::blockstore
{
    class MemoryBlockStore : public BlockStore, public FaultController
    {
    public:
        ~MemoryBlockStore() override = default;
        /** @copydoc BlockStore::Put() */
        result<PutOutcome, BlockStatus> Put(
            const Cid& cid, gsl::span<const uint8_t> bytes,
            const WriteOptions& options = {}) override;
```

**Factory + options struct** — copy `LocalBlockStore::Open` / `MinioS3Client::Open` precedent (`static result<std::unique_ptr<T>, BlockStatus> Open(...)`, `std::invalid_argument` on programmer error, options struct with defaulted members) — see `src/MinioS3Client.cpp:136-151`:

```cpp
// Source: thirdparty/sgns-blockstore/src/MinioS3Client.cpp:136-151
result<std::unique_ptr<MinioS3Client>, BlockStatus> MinioS3Client::Open(
    const S3ClientConfig& config)
{
    if (config.endpoint.empty() || config.bucket.empty())
    {
        throw std::invalid_argument(
            "sgns::blockstore: S3ClientConfig requires a non-empty "
            "endpoint and bucket");
    }
    auto client = std::unique_ptr<MinioS3Client>(new MinioS3Client());
    client->impl_ = std::make_unique<Impl>(config);
    return client;
}
```

`S3BlockStoreOptions` shape follows `LocalBlockStoreOptions` (`include/sgns-blockstore/LocalBlockStore.hpp`, `struct LocalBlockStoreOptions { std::string path; }`). Inject `std::shared_ptr<S3Client>` so tests keep a handle to the fake for key-layout observability (04-RESEARCH Pattern 1).

**Entry gate + verify-at-facade (impl)** — copy `MemoryBlockStore.cpp`'s `ValidateCidHash` + explicit `CidOf` mapping. NEVER `OUTCOME_TRY` a `CidOf` failure into a `BlockStatus` envelope (mismatched error types; Phase-1 landmine):

```cpp
// Source: thirdparty/sgns-blockstore/src/MemoryBlockStore.cpp (Put body)
ValidateCidHash(cid);
// NOTE: CidOf carries the default error type (std::error_code), so
// its failure is mapped explicitly - never OUTCOME_TRY'd across the
// BlockStatus-typed envelope (mismatched error types).
auto computed = CidOf(bytes, cid.content_type);
if (!computed)
{
    return BlockStatus{StatusClass::Corrupt, BlockSource::Caller,
                       "Put rejected: payload could not be hashed"};
}
if (!(computed.value() == cid))
{
    return BlockStatus{StatusClass::Corrupt, BlockSource::Caller,
                       "Put rejected: bytes do not hash to the claimed CID"};
}
```

S3 attribution delta (04-RESEARCH Pattern 1): Get-time verify failures use `BlockSource::Remote`, not `Caller` — bytes came from the remote.

**One-place status mapping — the discipline the store inherits** — the store maps `S3PutResult`/`S3HeadResult` → frozen envelope and NEVER touches HTTP. The mapper it composes over is already one-place in `MinioS3Client.cpp` (default bucket = `TemporarilyUnavailable`, NEVER `NotFound` — the CRDT-corruption trap):

```cpp
// Source: thirdparty/sgns-blockstore/src/MinioS3Client.cpp:74-96
BlockStatus MapMinioFailure(const std::string& error_string, const char* op)
{
    if (error_string.rfind("NoSuchKey:", 0) == 0
        || error_string.rfind("NoSuchBucket:", 0) == 0)
    {
        return BlockStatus{StatusClass::NotFound, BlockSource::Remote,
                           std::string(op) + ": " + error_string};
    }
    if (error_string.rfind("AccessDenied:", 0) == 0)
    {
        return BlockStatus{StatusClass::Unauthorized, BlockSource::Remote,
                           std::string(op) + ": " + error_string};
    }
    return BlockStatus{StatusClass::TemporarilyUnavailable,
                       BlockSource::Remote,
                       std::string(op) + ": " + error_string};
}
```

**Create-only semantics the store relays** — `S3BlockStore` always Puts with `createOnly=true`; 412 arrives at the adapter as the SUCCESS slot (the three-shape classifier, `MinioS3Client.cpp:23-45,186-204`):

```cpp
// Source: thirdparty/sgns-blockstore/src/MinioS3Client.cpp:186-204
if (options.createOnly)
{
    // THE conditional field: the ObjectWriteArgs headers Multimap
    // - verified on the wire in the 03-01 spike. NEVER
    // extra_headers: the pinned tag's single-part PUT path
    // silently drops that member (03-RESEARCH pitfall 2).
    args.headers.Add("If-None-Match", "*");
}
...
const std::string error = result.error().String();
if (IsPreconditionFailure(error))
{
    return S3PutResult{ /*achieved=*/true, /*alreadyPresent=*/true };
}
```

**PutMany** — copy the per-element vector loop, no all-or-nothing (01 D-14): `src/MemoryBlockStore.cpp` `PutMany` — "Per-element Put preserves index correspondence; a failed element never rolls back its siblings".

**Key derivation** — use `ContentIdentifierCodec::toString` (spike-proven, `test/cid_spike_test.cpp:64-78`); fan out on the first **digest** byte, never the CID string head (the `bafkrei` constant-prefix trap).

---

### `include/sgns-blockstore/UploadDrainer.hpp` + `src/UploadDrainer.cpp` (orchestration utility, batch)

**Analog:** `include/sgns-blockstore/BlockStoreTooling.hpp` (installed header that is NOT a data-path backend — the shape precedent for an installed non-BlockStore surface); loop semantics from `MemoryBlockStore::PutMany`; consumed surfaces from `LocalBlockStore.hpp` / `BlockStoreTooling.hpp`.

**Installed-header style** — copy `BlockStoreTooling.hpp`'s Doxygen banner + rationale-comment discipline:

```cpp
// Source: thirdparty/sgns-blockstore/include/sgns-blockstore/BlockStoreTooling.hpp:1-17
/**
 * @file BlockStoreTooling.hpp
 * @brief The tooling/audit-only enumeration surface (CORE-06).
 */
#ifndef SGNS_BLOCKSTORE_BLOCKSTORETOOLING_HPP
#define SGNS_BLOCKSTORE_BLOCKSTORETOOLING_HPP
```

**Surfaces the drainer composes (exact signatures, already shipped):**

```cpp
// Source: thirdparty/sgns-blockstore/include/sgns-blockstore/LocalBlockStore.hpp + BlockStoreTooling.hpp
result<std::vector<Cid>, BlockStatus> GetPendingUploads();      // tooling (02 D-05)
result<void, BlockStatus> MarkUploadedAccepted(const Cid& cid); // journal transition (02 D-06)
result<UploadState, BlockStatus> GetUploadState(const Cid& cid);
// enum class UploadState { PendingUpload, UploadedAccepted, UploadedDurable }
```

**Loop semantics** — copy `PutMany`'s outer-failure/per-item-split shape from `src/MemoryBlockStore.cpp`: enumeration failure (`GetPendingUploads`) → abort with wholesale `BlockStatus` envelope; per-item failures → recorded, siblings continue (D-03). Mark `MarkUploadedAccepted` ONLY on success-slot (`achieved` OR `alreadyPresent`) outcomes — D-04; never `MarkUploadedDurable`. Return shape per 04-RESEARCH Pattern 3 (`DrainItem { Cid cid; result<PutOutcome, BlockStatus> upload; result<void, BlockStatus> journal; }` — planner may adjust at discretion, but the per-item vector contract is locked by D-03).

---

### `include/sgns-blockstore/S3Client.hpp` — promotion from `src/S3Client.hpp` (provider interface, request-response)

**Analog:** itself (git mv). Mechanics verified this session:

1. **Install is automatic** — the root install rule pattern-matches `include/`:
```cmake
# Source: thirdparty/sgns-blockstore/CMakeLists.txt:52-54
install(DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/include/"
    ...
    FILES_MATCHING PATTERN "*.hpp")
```
2. **Rewrite the header's own stale doc banner** — `src/S3Client.hpp:5-9` currently says "NOT INSTALLED (D-04): this header lives in src/ ... It is promoted to an installed header only with Phase 4's S3BlockStore" — that comment IS this phase; replace with the promotion reality + the CORE-05/03-D-03 `Delete` reconciliation note (04-RESEARCH Pattern 4 item 5).
3. **Include swaps** in `src/InMemoryS3Client.hpp` (currently `#include "S3Client.hpp"` at line 20) and `src/MinioS3Client.hpp` → `#include <sgns-blockstore/S3Client.hpp>`. The two impl headers STAY in `src/` (SDK-free by pimpl; tests reach them via the `target_include_directories(... ${CMAKE_SOURCE_DIR}/src)` privilege — `test/CMakeLists.txt:76-84` precedent).
4. **Header hygiene gate passes as-is** — `S3Client.hpp` includes only `<cstdint> <string> <vector> <sgns-blockstore/BlockStatus.hpp> <sgns-blockstore/Cid.hpp>` (verified this session; `test/header_hygiene_check.cmake` bans `minio` etc. in installed headers).
5. **Deployed-tree staleness** — after the move, rebuild dependents (`/t:Rebuild`) and verify the deployed `include/` tree actually carries the header (Windows superbuild wrapper-vcxproj trap; 04-RESEARCH Pitfall 6).

---

### `test/s3_block_store_test.cpp` (test, conformance + key layout)

**Analog:** `test/memory_block_store_test.cpp:381-392` — one macro line per suite; factory invoked PER CASE (fresh fake per case):

```cpp
// Source: thirdparty/sgns-blockstore/test/memory_block_store_test.cpp:380-392
// Plan-03 kit instantiation (the marker from Plan 02): one macro line per
// suite; two distinct suite names prove coexistence in one binary.
SGNS_BLOCKSTORE_CONFORMANCE_TESTS(
    MemoryBlockStoreConformance,
    [] { return std::shared_ptr<sgns::blockstore::BlockStore>(
        std::make_shared<sgns::blockstore::MemoryBlockStore>()); })
```

For `S3BlockStore` the factory opens a store over a FRESH `InMemoryS3Client`. Kit contract (from `test/conformance/BlockStoreConformanceTests.hpp:5-20`): plain GTest `EXPECT/ASSERT` + manual `.value()`/.error()`, zero outcome macros; kit is NEVER installed, reached via `target_include_directories(... ${CMAKE_SOURCE_DIR}/test/conformance)`.

**Key-layout observability** — assert the derived key for the known vector CID against a literal computed via `ContentIdentifierCodec::toString` on the SAME fixture CID (`test/cid_spike_test.cpp:64-78` known vector: `"bafkreifzjut3te2nhyekklss27nh3k72ysco7y32koao5eei66wof36n5e"` for `"hello world"` — but beware 04-RESEARCH Pitfall 8: the kit's fixtures are `"conformance payload a/b"`, don't paste the `hello world` literal next to them). The fake's `objects_` map (`src/InMemoryS3Client.hpp`, private `std::map<std::string, std::vector<uint8_t>> objects_`) is the probe surface — expose read access for tests if needed (test-only seam precedent: `SetFault` marked "CONFORMANCE-TEST SEAM: production code MUST NOT call this").

---

### `test/upload_drainer_test.cpp` (test, batch)

**Analog:** `test/local_block_store_test.cpp:336-375` — journal-transition assertion pattern the drainer must reproduce (`GetUploadState` + `GetPendingUploads` + byte-identity triple-check):

```cpp
// Source: thirdparty/sgns-blockstore/test/local_block_store_test.cpp:360-375
TEST_F(LocalBlockStoreTest, MarkUploadedAcceptedMovesStateAndShrinksPending)
{
    ASSERT_NE(store_, nullptr);
    ASSERT_TRUE(store_->Put(cid_a_, SpanOf(payload_a_)));
    ASSERT_TRUE(store_->MarkUploadedAccepted(cid_a_));
    auto state = store_->GetUploadState(cid_a_);
    ASSERT_TRUE(state);
    EXPECT_EQ(state.value(), UploadState::UploadedAccepted);
    auto pending = store_->GetPendingUploads();
    ASSERT_TRUE(pending);
    EXPECT_TRUE(pending.value().empty());
    ...
}
```

Drainer tests drive the same assertions THROUGH `DrainPendingUploads(local, fakeBackedS3BlockStore)` with the fake as remote: per-item outcome shape, continue-on-failure (script fake faults via `SetFault(S3Op::Put, ...)`), re-drain retries only still-pending (D-03), journal advances only on remote-present outcomes (D-04).

---

### `test/s3_block_store_minio_test.cpp` + `test/s3d_spike_test.cpp` (env-gated integration tier)

**Analog:** `test/minio_cpp_spike_test.cpp:252-310` + the existing MinIO-tier CMake entries (`test/CMakeLists.txt:88-108`).

**Env-gate + loud labelled skip (THE pattern)**:

```cpp
// Source: thirdparty/sgns-blockstore/test/minio_cpp_spike_test.cpp:262-278
TEST(MinioCppSpikeTest, EnvGatedTlsOnSmoke)
{
    if (!MinioServerHarness::Available())
    {
        GTEST_SKIP() << "[SGNS_BLOCKSTORE][MINIO-TIER] binary not provided "
                        "(set SGNS_BLOCKSTORE_TEST_MINIO_BIN)";
    }
    MinioServerHarness harness;
    std::string error;
    if (!harness.Start(/*tls=*/true, &error))
    {
        GTEST_SKIP() << "[SGNS_BLOCKSTORE][MINIO-TIER] TLS fixture "
                        "unavailable: " << error;
    }
    ASSERT_TRUE(harness.MakeBucket("spike-bucket", &error)) << error;
```

- MinIO tier (S3D-01): instantiate `MinioServerHarness` UNCHANGED (`Start(tls)` / `MakeBucket` / `AccessKey()` / `SecretKey()` — `test/MinioServerHarness.hpp:63-113`), driven through `MinioS3Client` → `S3BlockStore`.
- s3d tier: env-VAR endpoint config, loud skip label `[SGNS_BLOCKSTORE][S3D-TIER]` (mirrors the MINIO-TIER label), **NEVER spawns s3d** (D-08) — this is the key deviation from the harness analog: no child process, dev-managed server only.
- CMake wiring per tier: hermetic suites link exactly `sgns-blockstore + p2p::p2p_cid` (default CI lane); MinIO/s3d tiers additionally compile `MinioServerHarness.cpp` and link `miniocpp::miniocpp OpenSSL::Crypto OpenSSL::SSL` (+ `ws2_32` on WIN32) — copy `test/CMakeLists.txt:44-63` / `88-108`.

---

### `test/s3d_roundtrip_e2e.cpp` (dev-gated two-run E2E)

**Analog (partial):** env-gate/loud-skip from `minio_cpp_spike_test.cpp:264-267`; evidence discipline from `03-04-live-run-evidence.log`.

No in-repo analog exists for the two-run fresh-process design (upload/verify modes, run-state handoff file, unique-per-run CID). Planner follows 04-RESEARCH Pattern 5 verbatim: one binary, two GTest cases selected via `--gtest_filter` (two invocations ARE the two processes); run A = `LocalBlockStore.Put` → `DrainPendingUploads` → assert `UploadedAccepted`; run B = fresh `S3BlockStore` → `Get` → CID-verify; state handoff via env-var file path (`SGNS_BLOCKSTORE_TEST_S3D_RUN_STATE`); env-var surface `SGNS_BLOCKSTORE_TEST_S3D_{ENDPOINT,ACCESS_KEY,SECRET_KEY,BUCKET,USE_TLS,...}`.

**Evidence-log format warning (verified this session):** `03-04-live-run-evidence.log` is a **UTF-16LE** PowerShell redirect (hex dump confirms `fe ff`-style byte pairs). Phase 4's log MUST be captured as ASCII/UTF-8 for diffability (04-RESEARCH Pattern 5 note). No secrets — endpoint host at most.

---

### `test/api_hygiene_test.cpp` (modified) — include-everything TU + negative traits

**Analog:** itself. Three changes required (04-RESEARCH Pitfall 1):

1. Extend the include block (`test/api_hygiene_test.cpp:38-48`, currently ends at `LocalBlockStore.hpp`) with the promoted `S3Client.hpp` + the two new headers.
2. Rewrite the now-stale comment at `api_hygiene_test.cpp:52-59` ("The S3Client seam itself stays internal (D-04; src/ headers, asserted by the Head/Delete negative traits below)") to the promotion reality.
3. Extend the negative traits — the `HasHead`/`HasDelete` trait machinery already exists (`api_hygiene_test.cpp` ~166-190); add:
```cpp
static_assert(!HasHead<sgns::blockstore::S3BlockStore>::value, ...);
static_assert(!HasDelete<sgns::blockstore::S3BlockStore>::value, ...);
```

---

### Build wiring: `src/CMakeLists.txt` + `test/CMakeLists.txt` (modified)

**Analog:** themselves.

```cmake
# Source: thirdparty/sgns-blockstore/src/CMakeLists.txt:1-7  (add S3BlockStore.cpp / UploadDrainer.cpp here)
add_library(sgns-blockstore STATIC
    Cid.cpp
    ContractHeaders.cpp
    InMemoryS3Client.cpp
    LocalBlockStore.cpp
    MemoryBlockStore.cpp
    MinioS3Client.cpp
)
```

Test entries copy the `addtest(<name> <src>.cpp)` + `target_link_libraries(<name> sgns-blockstore p2p::p2p_cid)` + optional `target_include_directories(<name> PRIVATE ${CMAKE_SOURCE_DIR}/test/conformance)` / `${CMAKE_SOURCE_DIR}/src` pattern visible throughout `test/CMakeLists.txt:1-108`. **`thirdparty/build/CommonTargets.cmake` needs NO change** (verified: `ExternalProject_Add(sgns-blockstore ...)` at `CommonTargets.cmake:863-919` already passes every needed cache arg).

---

### `include/sgns-blockstore/Durability.hpp` (modified) — doc citation (D-12)

**Analog:** itself. Extend the `ObjectStoreAccepted` doc comment to cite `docs/s3d-durability.md`:

```cpp
// Source: thirdparty/sgns-blockstore/include/sgns-blockstore/Durability.hpp:14-24
/**
 * @brief The durability acknowledgment levels a store can report.
 *
 * Verbatim from supergenius-sharded-ipld-cache-architecture.md. The
 * distinction between ObjectStoreAccepted and ObjectStoreDurable
 * matters for Sia s3d: an acknowledged upload may initially reside in
 * durable local staging before background transfer. `PeerReplicated`
 * is the placeholder anchoring future eviction work.
 */
enum class DurabilityLevel
{
    LocalCommitted,      ///< bytes are in locally-committed storage
    PeerReplicated,     ///< bytes are replicated across peers (v1 placeholder)
    ObjectStoreAccepted, ///< object store acknowledged receipt (not yet proven durable)
    ObjectStoreDurable,  ///< object store has proven durable storage
};
```

The citation grounds "200-OK ≠ durable" in the committed characterization (D-12); every claim in the doc must trace to a spike artifact (D-13).

---

### Evidence artifacts: `04-XX-live-run-evidence.log` + `docs/evidence/s3d-spike/*`

**Analog:** `.planning/workstreams/rocksdb-backup/phases/03-minio-cpp-integration-s3client-adapter/03-04-live-run-evidence.log` (tracked, verified). Content: raw test output per run, CIDs, object keys, sizes, timestamps, backend version (`s3d version`), pass/fail. Deltas for Phase 4: UTF-8/ASCII capture (not UTF-16LE), both runs of the E2E in one log, endpoint host at most / never credentials (D-11 + `BlockStatus` "message content must NEVER embed secrets" rule — `MapMinioFailure` already obeys it).

## Shared Patterns

### Result envelope (MANDATORY in every new header)

**Source:** `thirdparty/sgns-blockstore/include/sgns-blockstore/Cid.hpp:~28-44`
**Apply to:** `S3BlockStore.hpp`, `UploadDrainer.hpp`, all new tests

```cpp
namespace outcome = libp2p::outcome;
template <class R, class S = std::error_code,
          class NoValuePolicy = libp2p::outcome::policy::terminate>
using result = libp2p::outcome::basic_result<R, S, NoValuePolicy>;
```

`policy::terminate` is deliberate — `.value()` on failure TERMINATES. Guard with `if (!res)` / `has_value()` everywhere; map `CidOf` failures explicitly (never `OUTCOME_TRY` across the envelope).

### One-place status mapping per backend

**Source:** `src/MinioS3Client.cpp:74-96` (`MapMinioFailure`); precedents `src/MemoryBlockStore.cpp`, `src/LocalBlockStore.cpp`
**Apply to:** `src/S3BlockStore.cpp` — maps ADAPTER results (`S3PutResult`/`S3HeadResult`) into the frozen envelope; raw HTTP never crosses. Default failure bucket is `TemporarilyUnavailable`, never `NotFound`. No credentials/config fields ever concatenated into messages.

### Env-gated tier + loud labelled skip

**Source:** `test/minio_cpp_spike_test.cpp:264-267` + `test/MinioServerHarness.hpp:17-18,36-38`
**Apply to:** `test/s3_block_store_minio_test.cpp`, `test/s3d_spike_test.cpp`, `test/s3d_roundtrip_e2e.cpp` — gate on env var, `GTEST_SKIP() << "[SGNS_BLOCKSTORE][<TIER>-TIER] ..."` when unset, no auto-download, no fixed sleeps, runtime-skip never a CMake gate.

### Public-header Doxygen + install discipline

**Source:** `MemoryBlockStore.hpp` / `BlockStoreTooling.hpp` / `LocalBlockStore.hpp`
**Apply to:** all new/modified installed headers — `@file/@brief` banner, guard `SGNS_BLOCKSTORE_<NAME>_HPP`, `<sgns-blockstore/...>` include style, `@brief/@param/@return/@note` on every public symbol, Ullman braces, PascalCase types, trailing-underscore members, `result<...>` returns, factory `Open()` + `create()`-style lower-noise. Installed automatically by `CMakeLists.txt:52-54` (`FILES_MATCHING PATTERN "*.hpp"`); `header_hygiene_check.cmake` bans SDK-shaped includes — `S3Client.hpp` passes as-is (verified).

### Per-item, no-all-or-nothing batch semantics

**Source:** `src/MemoryBlockStore.cpp` `PutMany` (D-14 comment: "a failed element never rolls back its siblings")
**Apply to:** `UploadDrainer.cpp` (D-03) — outer failure aborts wholesale; per-item failures record-and-continue; re-drain retries only still-pending items.

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `docs/s3d-durability.md` | documentation | — | `thirdparty/sgns-blockstore` has NO `docs/` directory and NO README (verified via `git ls-files`); this is the repo's first prose doc. Planner uses 04-RESEARCH Pattern 6 + Code Examples (verbatim `openapi.yml` `UploadStats` schema, spike captures) with the Doxygen doc-comment conventions as the style baseline. |

Partial (mechanics novel, gating pattern exists): `test/s3d_roundtrip_e2e.cpp` two-run fresh-process mode/handoff design — follow 04-RESEARCH Pattern 5.

## Metadata

**Analog search scope:** `thirdparty/sgns-blockstore/{include,src,test}` (full tracked inventory, 38 files), `thirdparty/build/CommonTargets.cmake:855-925`, `.planning/workstreams/rocksdb-backup/phases/03-*`
**Files read for excerpts:** 16
**Tracked-source gate:** all named analogs pass (`git ls-files` verified in nested sgns-blockstore repo, thirdparty repo, outer repo)
**Pattern extraction date:** 2026-10-21
