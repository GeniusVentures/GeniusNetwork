# Phase 6: sgns-blockstore v1.1 Library Prerequisites — Pattern Map

**Mapped:** 2026-10-22
**Files analyzed:** 19 (17 modified, 2 created)
**Analogs found:** 17 / 19 (2 created files have only partial/role-match analogs — see No Analog Found)

**Tracked-source gate (#3645):** every analog named below verified `git ls-files`-tracked this session (sgns-blockstore submodule, ipfs-lite-cpp submodule, and the thirdparty superbuild repo). The one near-miss — `thirdparty/build/Windows/Debug/sgns-blockstore-smoke/` — is an **untracked build artifact**; it is prior art to inspect, never an analog to cite.

This is a **widening phase**: the dominant pattern class is *in-file analog* — each modified file's own existing code is the exact pattern to extend. Every excerpt below was read from the tree this session.

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `thirdparty/sgns-blockstore/include/sgns-blockstore/Cid.hpp` | model (public API header) | transform | same file: 2-arg `CidOf` decl + doc block (lines 58–77) | exact (in-file) |
| `thirdparty/sgns-blockstore/src/Cid.cpp` | utility impl | transform | same file: sha-256 path (15–31); target shape: `thirdparty/ipfs-lite-cpp/primitives/cid/cid.cpp:128-136` | exact |
| `thirdparty/sgns-blockstore/src/MemoryBlockStore.cpp` | service (backend) | CRUD + batch | same file: `ValidateCidHash` (23–33), verify sites (71, 108), PutMany pre-pass (~157) | exact (in-file) |
| `thirdparty/sgns-blockstore/src/LocalBlockStore.cpp` | service (backend) | CRUD + batch | same file: gate (35–45), verify (305, 427), pre-pass (~532) | exact (in-file) |
| `thirdparty/sgns-blockstore/src/S3BlockStore.cpp` | service (backend) | CRUD + batch | same file: gate (27–37), `CodecToken` (42–53), verify (124, 177), `DeriveKey` (~100–115) | exact (in-file) |
| `thirdparty/sgns-blockstore/include/sgns-blockstore/S3Client.hpp` | interface header | request-response (factory) | same file: `S3ClientConfig` (77–92) + `MinioS3Client::Open` shape (`src/MinioS3Client.hpp:44-56`) | exact |
| `thirdparty/sgns-blockstore/src/MinioS3Client.cpp` | service impl | request-response | same file: `MinioS3Client::Open` (137–150) | exact (in-file) |
| `thirdparty/sgns-blockstore/src/MinioS3Client.hpp` | interface (internal) | — | — | **expected unchanged** (factory is a free function; `.cpp` already includes this header) |
| `thirdparty/sgns-blockstore/test/conformance/BlockStoreConformanceTests.hpp` | test kit (macro suite) | CRUD + batch | same file: `MakeBlake2bCid` (52–67), rejection tests (195–251); vector pinning: `test/cid_spike_test.cpp:66-73` | exact |
| `thirdparty/sgns-blockstore/test/memory_block_store_test.cpp` | test | CRUD + batch | same file: `Blake2bCidThrowsInvalidArgument` (196–207), `PutManyBlake2bThrowsAndWritesNothing` (338–350) | exact (in-file) |
| `thirdparty/sgns-blockstore/test/local_block_store_test.cpp` | test | CRUD + batch | same file: `Blake2bCid()` helper (62–79), `TransitionsRespectEntryGates` (~487–497) | exact (in-file) |
| `thirdparty/sgns-blockstore/test/s3_block_store_test.cpp` | test | CRUD + batch | same file: `KeyLayoutKnownVectorHelloWorld` (60–97), kit instantiation (495–506) | exact (in-file) |
| `thirdparty/sgns-blockstore/cmake/config.cmake.in` | config (package) | — | same file: `find_dependency(RocksDB CONFIG)` (line 4) | exact (in-file) |
| `thirdparty/sgns-blockstore/CMakeLists.txt` | config (build) | — | same file: httplib/miniocpp `find_package` block (35–44) | exact (in-file) |
| `thirdparty/sgns-blockstore/src/CMakeLists.txt` | config (build) | — | same file: `PRIVATE miniocpp::miniocpp` link (13–19) | exact (in-file) |
| `thirdparty/sgns-blockstore/test/CMakeLists.txt` | config (test registration) | — | same file: `addtest` + `set_tests_properties(... LABELS "Tier1")` (1–7, 216–226) | exact (in-file) |
| `thirdparty/build/CommonTargets.cmake` | config (superbuild) | — | same file: sgns-blockstore entry (863–920) + ipfs-pubsub's `-Dipfs-lite-cpp_DIR` hint (545–562) | exact (in-file) |
| `thirdparty/sgns-blockstore/test/out_of_tree_consumer/` (CMakeLists.txt + TU) **CREATED** | test (out-of-tree consumer) | request-response | `sgns-blockstore/CMakeLists.txt` find_package/install pattern (partial); no tracked standalone-consumer analog exists | partial |
| `thirdparty/sgns-blockstore/docs/evidence/blake2b-crosscheck/getcidof-crosscheck.log` **CREATED** | evidence artifact | file-I/O (dev-run output) | `docs/evidence/s3d-spike/*` (tracked, committed) + `.planning/.../03-minio-cpp-integration-s3client-adapter/03-04-live-run-evidence.log` (dated-section dev-run log) | role-match |

## Pattern Assignments

### 1. `Cid.hpp` + `Cid.cpp` — 3-arg `CidOf` overload (LIB-01 / D-04)

**Analog (declaration):** `include/sgns-blockstore/Cid.hpp` lines 58–77 — copy this exact doc shape for the overload; the `@note` text must be rewritten to describe the widened pair {sha-256, blake2b-256} (it currently documents the sha-256-only D-08 posture):

```cpp
    /**
     * @brief Construct the verified CID for a block payload.
     * ...
     * @param bytes the block payload to hash
     * @param codec the content codec the CID records (e.g. RAW, DAG_PB)
     * @return the CIDv1 carrying a sha-256 multihash, or error
     *
     * @note v1 hashes with sha-256 multihash ONLY (decision D-08): ...
     */
    outcome::result<Cid> CidOf(gsl::span<const uint8_t> bytes,
                               libp2p::multi::MulticodecType::Code codec);
```

Include block to extend (lines 8–12 — `HashType` is already visible transitively via `content_identifier.hpp` → `multihash.hpp` → `hash_type.hpp`; **zero new includes needed** → hygiene stays green):

```cpp
#include <gsl/span>
#include <libp2p/multi/content_identifier.hpp>
#include <libp2p/multi/multicodec_type.hpp>
#include <libp2p/outcome/outcome.hpp>
```

**Analog (implementation):** `src/Cid.cpp` lines 15–31 — the sha-256 branch of the new 3-arg overload is literally this body; note the file-local comment about OUTCOME_TRY's auto-injection:

```cpp
    outcome::result<Cid> CidOf(gsl::span<const uint8_t> bytes,
                               libp2p::multi::MulticodecType::Code codec)
    {
        // libp2p::crypto::sha256 returns outcome::result<libp2p::common::Hash256>,
        // where Hash256 = std::array<uint8_t, 32>. Note: the vendored
        // OUTCOME_TRY wrapper injects `auto` itself - pass the bare name.
        OUTCOME_TRY(digest, libp2p::crypto::sha256(bytes));
        OUTCOME_TRY(hash,
                    libp2p::multi::Multihash::create(
                        libp2p::multi::HashType::sha256,
                        gsl::span<const uint8_t>(digest.data(), digest.size())));
        return Cid(Cid::Version::V1, codec, std::move(hash));
    }
```

**Target composition (blake2b branch) — the ground-truth analog:** `thirdparty/ipfs-lite-cpp/primitives/cid/cid.cpp:128-136` (`sgns::common::getCidOf`, the real CRDT producer). Mirror these three steps exactly, substituting the blake2b call:

```cpp
    IPFS::outcome::result<CID> getCidOf( gsl::span<const uint8_t> bytes )
    {
        auto hash_raw = crypto::blake2b::blake2b_256( bytes );
        BOOST_OUTCOME_TRY( auto hash, Multihash::create( HashType::blake2b_256, hash_raw ) );
        return CID( CID::Version::V1, CID::Multicodec::DAG_CBOR, hash );
    }
```

**blake2b entry point** (tracked: `thirdparty/ipfs-lite-cpp/crypto/blake2/blake2b160.hpp:10-32`) — `Blake2b256Hash blake2b_256(gsl::span<const uint8_t>)` returning `common::Blob<32>`; the only include `src/Cid.cpp` gains (it appears ONLY in src/, never in an installed header — Q10 hygiene). The 2-arg form delegates: `return CidOf(bytes, codec, libp2p::multi::HashType::sha256);` — literally untouched signature.

**Throw pattern for unsupported HashType:** copy the gate-throw style from §2 (message prefix `"sgns::blockstore: ..."`, `std::invalid_argument`).

---

### 2. Backend gate widening + verify branching — `MemoryBlockStore.cpp`, `LocalBlockStore.cpp`, `S3BlockStore.cpp`

**Analog (gate):** three byte-identical anonymous-namespace functions. `MemoryBlockStore.cpp:23-33` (Local 35–45, S3 27–37 are identical bodies — Local's doc comment says "Verbatim from the MemoryBlockStore reference backend"):

```cpp
        void ValidateCidHash(const Cid& cid)
        {
            if (cid.content_address.getType() != libp2p::multi::HashType::sha256)
            {
                throw std::invalid_argument(
                    "sgns::blockstore: CID multihash type is not sha-256 - "
                    "v1 accepts sha-256 CIDs only (D-08; blake2b CRDT CIDs "
                    "are a documented v1 non-goal)");
            }
        }
```

Widening = condition becomes `(type != sha256 && type != blake2b_256)`; message text updated **once** (it names "sha-256 only" — this is the strongest argument for the discretionary consolidation into one internal `src/` header, e.g. `src/CidGate.hpp`, used by all three TUs). Throw contract unchanged (D-03).

**Analog (verify-on-put):** `S3BlockStore.cpp` ~117–131 (Memory ~71, Local ~305 are the same shape; Memory/Local/S3 Put all: gate → `computed = CidOf(bytes, cid.content_type)` → two Corrupt branches):

```cpp
        ValidateCidHash(cid);
        ...
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

All six sites (Put: Memory 71 / Local 305 / S3 124; Get-verify: Memory 108 / Local 427 / S3 177) change **one token-line** each: `CidOf(bytes, cid.content_type)` → `CidOf(bytes, cid.content_type, cid.content_address.getType())`. Error-mapping branches and messages stay untouched (unsupported-hash is unreachable past the gate — D-03 ordering). Get-verify keeps its per-backend attribution: Memory→`BlockSource::Memory` ("stored bytes failed CID re-verification"), Local→`BlockSource::Local`, S3→`BlockSource::Remote` ("fetched bytes failed...") — the byte-flip blake2b test asserts these enums.

**Analog (PutMany pre-validation):** `MemoryBlockStore.cpp` ~154–160 (Local ~532, S3 ~244 identical):

```cpp
        // D-08 pre-validation of the WHOLE batch before any write: a
        // mid-batch throw can never leave partial writes behind.
        for (const auto& input : blocks)
        {
            ValidateCidHash(input.cid);
        }
```

Rides the gate widening automatically — no per-site edit beyond (optional) the D-08 comment tag.

---

### 3. `CodecToken` dag-cbor case — `S3BlockStore.cpp:42-53`

**Analog:** the existing switch, verbatim. Add one `case DAG_CBOR: return "dag-cbor";` — `unknown-codec` catch-all stays (discretion):

```cpp
        const char* CodecToken(libp2p::multi::MulticodecType::Code codec)
        {
            switch (codec)
            {
                case libp2p::multi::MulticodecType::Code::RAW:
                    return "raw";
                case libp2p::multi::MulticodecType::Code::DAG_PB:
                    return "dag-pb";
                default:
                    return "unknown-codec";
            }
        }
```

Key composition site (`DeriveKey`, ~113–115): `keyPrefix_ + '/' + CodecToken(cid.content_type) + '/' + DigestFanoutByte(cid) + '/' + cid_string.value()` — a DAG_CBOR block lands at `v1/blocks/dag-cbor/<xx>/<bafyre...>`, asserted via `InMemoryS3Client::ObjectKeys()` per §5's key-layout test. `DeriveKey`'s doc comment (~100–107) says "practically unreachable for sha256" — planner may refresh the comment to name the widened pair.

---

### 4. `S3Client.hpp` factory declaration + `MinioS3Client.cpp` definition (LIB-02 / D-05, D-06)

**Analog (factory shape + Doxygen contract):** `src/MinioS3Client.hpp:44-56` — copy this doc structure for the free-function declaration in installed `S3Client.hpp` (add the D-06 eager-validation/zero-network-I/O contract and the BaseUrl-snapshot note):

```cpp
        /**
         * @brief Factory mirroring LocalBlockStore::Open.
         * @param config endpoint/credentials/bucket; tlsVerify is the ONLY
         *        TLS-verification control (default true, T-3-02)
         * @throws std::invalid_argument on programmer error (empty
         *         endpoint or bucket), exactly as the Phase-2 empty-path
         *         check does
         */
        static result<std::unique_ptr<MinioS3Client>, BlockStatus> Open(
            const S3ClientConfig& config);
```

Locked signature (D-05): `result<std::shared_ptr<S3Client>, BlockStatus> OpenMinioS3Client(const S3ClientConfig& config);` — placed in `namespace sgns::blockstore` beside `S3ClientConfig` (S3Client.hpp 77–92). Zero new includes (BlockStatus/Cid/result already included at lines 55–57) → hygiene green by construction.

**Analog (definition):** `src/MinioS3Client.cpp:137-150` — the wrapper's body wraps exactly this; note the throw-for-programmer-error precedent (keep-throw per RESEARCH Open Question 2):

```cpp
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

Wrapper mechanics: `auto opened = MinioS3Client::Open(config); if (!opened) return opened.error(); return std::shared_ptr<S3Client>(std::move(opened.value()));` — `shared_ptr` type-erases the deleter, so the consumer never needs the complete `MinioS3Client` type; define it in `MinioS3Client.cpp` (already sees the internal header; **no new TU**). Secondary throw precedent: `S3BlockStore::Open` (S3BlockStore.cpp ~80–96) throws `invalid_argument` for null client / empty prefix — same "throw for programmer error, result for runtime failure" split.

---

### 5. `BlockStoreConformanceTests.hpp` — vector suite + rejection retarget

**Analog (helper to keep + repurpose):** `MakeBlake2bCid()` at lines 52–67 — after widening, its fake-digest/RAW shape remains valid ONLY as a no-payload gate probe (Has/GetSize/PutMany); real roundtrip vectors need real blake2b digests + DAG_CBOR codec:

```cpp
    inline Cid MakeBlake2bCid()
    {
        // The CRDT CBOR boundary shape that must throw at API entry (D-08).
        static const uint8_t digest[32] = { 0xb1, 0xb2, ... , 0x1f, 0x20, };
        return Cid(Cid::Version::V1, libp2p::multi::MulticodecType::Code::RAW,
                   libp2p::multi::Multihash::create(
                       libp2p::multi::HashType::blake2b_256,
                       gsl::span<const uint8_t>(digest, 32)).value());
    }
```

New `MakeSha512Cid()` (re-target exemplar, discretion → RESEARCH recommends sha-512: `HashType::sha512`, 64-byte fake digest — fits `Multihash::kMaxHashLength = 127`, so the *gate* provably throws, not the multihash ctor) mirrors this helper with a 64-byte array. A real-digest vector helper `MakeDagCborBlake2bCid(payload)` composes `CidOf(bytes, DAG_CBOR, blake2b_256)` — the 3-arg overload under test.

**Analog (rejection tests to re-target):** lines 195–201 and ~237–251 (instantiated 3× via the macro):

```cpp
    TEST_F(SuiteName, PutNonSha256HashThrowsInvalidArgument)                   \
    {                                                                          \
        using sgns::blockstore::conformance::SpanOf;                           \
        EXPECT_THROW(                                                          \
            (void)store_->Put(sgns::blockstore::conformance::MakeBlake2bCid(), \
                              SpanOf(payload_a_)),                             \
            std::invalid_argument);                                            \
    }                                                                          \
```

Retarget = swap the helper to `MakeSha512Cid()` + rename (`PutNonSha256HashThrows...` → e.g. `PutRejectedHashThrowsInvalidArgument`); the blake2b slot flips to a roundtrip suite beside `PutGetRoundTrip` (line ~93) using the pinned vectors. New cases per RESEARCH Wave-1 step 6: blake2b/DAG_CBOR roundtrip (3 backends via macro), byte-flip Corrupt-with-attribution (pattern: `PutMismatchedBytesIsCorruptWithCallerSource`, ~173–185), dag-cbor key-layout observable, PutMany mixed-batch retarget.

**Analog (known-vector pinning discipline — the model comment):** `test/cid_spike_test.cpp:66-73`. Every pinned literal in the new suite carries this two-source cross-check provenance note (D-02 exists because of this exact precedent — a research-doc constant had a transcription error at position 33):

```cpp
    // Known vector: sha256("hello world") CIDv1 raw.
    // Regenerated and cross-checked during the spike against an independent
    // from-scratch base32 computation of 0x01 0x55 0x12 0x20 || sha256
    // digest: the research-doc constant had a transcription error at
    // position 33 ('w' instead of 'y') - the runtime codec and the
    // independent computation agree; details recorded in the plan SUMMARY.
    EXPECT_EQ(str_result.value(),
              "bafkreifzjut3te2nhyekklss27nh3k72ysco7y32koao5eei66wof36n5e");
```

**Analog (key-layout observable):** `test/s3_block_store_test.cpp:60-97` (`KeyLayoutKnownVectorHelloWorld`) — derive the expected key in-test from `ContentIdentifierCodec::toString` + first-digest-byte hex, then pin the full literal:

```cpp
    const std::string expected =
        "v1/blocks/raw/" + fanout + "/" + cid_string.value();
    EXPECT_EQ(keys[0], expected);
    // Known-vector pin (sha256("hello world") = b94d27b9...):
    EXPECT_EQ(expected,
              "v1/blocks/raw/b9/"
              "bafkreifzjut3te2nhyekklss27nh3k72ysco7y32koao5eei66wof36n5e");
```

dag-cbor variant: same test shape, token `"dag-cbor"`, blake2b digest fan-out byte.

---

### 6. Per-backend test retarget — `memory_block_store_test.cpp`, `local_block_store_test.cpp`

**Analog:** `memory_block_store_test.cpp:196-207` — each `Blake2bCid()` → `Sha512Cid()`-style helper; blake2b gains its own acceptance cases:

```cpp
TEST_F(MemoryBlockStoreTest, Blake2bCidThrowsInvalidArgument)
{
    const Cid bad = Blake2bCid();
    EXPECT_THROW((void)store_->Put(bad, SpanOf(payload_a_)), std::invalid_argument);
    EXPECT_THROW((void)store_->Get(bad), std::invalid_argument);
    EXPECT_THROW((void)store_->Has(bad), std::invalid_argument);
    const BlockInput batch[] = {{bad, SpanOf(payload_a_)}};
    EXPECT_THROW((void)store_->PutMany(batch), std::invalid_argument);
}
```

`PutManyBlake2bThrowsAndWritesNothing` (338–350) — same retarget; keep the `EXPECT_FALSE(store_->Has(cid_a_).value()); // nothing written` assertion shape for the sha-512 version.

`local_block_store_test.cpp`: `Blake2bCid()` helper at 62–79 (fake digest, RAW codec — identical construction pattern to the kit's) and the journal-tooling gates at ~490–492 inside `TransitionsRespectEntryGates` — these call the same store gate so they **widen automatically**; their blake2b rejection assertions re-target sha-512 and blake2b acceptance assertions join (RESEARCH Open Question 4).

`s3_block_store_test.cpp` has no standalone blake2b test (rides the macro at 495–506) — only the key-layout addition from §5 touches it.

---

### 7. CMake wiring — 5 files

**7a. `src/CMakeLists.txt`** — PRIVATE-link analog (lines 13–19); blake2 rides the identical mechanism (and will appear in the export as `$<LINK_ONLY:ipfs-lite-cpp::blake2>`, forcing the config.cmake.in `find_dependency` in Wave 2):

```cmake
target_link_libraries(sgns-blockstore
    PUBLIC p2p::p2p_cid
    PUBLIC RocksDB::rocksdb
    # minio-cpp stays PRIVATE: no installed header references it ...
    PRIVATE miniocpp::miniocpp
)
```

Add `PRIVATE ipfs-lite-cpp::blake2` with a comment in this house style.

**7b. Root `CMakeLists.txt`** — find_package-with-spike-comment analog (35–44, the httplib QUIET-find trap note is the commenting model for the new `find_package(ipfs-lite-cpp CONFIG REQUIRED)`):

```cmake
find_package(httplib CONFIG REQUIRED)
find_package(miniocpp CONFIG REQUIRED)
```

Preserve: `option(TESTING ...)` gate (46–54, deliberately named TESTING never BUILD_TESTING) and install rules (60–84: `FILES_MATCHING PATTERN "*.hpp"` — both new declarations ride existing rules; nothing new to install).

**7c. `cmake/config.cmake.in`** — current file in full (6 lines); hardening = additional `find_dependency(libp2p CONFIG)`, `find_dependency(miniocpp CONFIG)`, `find_dependency(ipfs-lite-cpp CONFIG)` before the targets include, exactly as the SC4 proof forces (D-07):

```cmake
@PACKAGE_INIT@

include(CMakeFindDependencyMacro)
find_dependency(RocksDB CONFIG)

include ( "${CMAKE_CURRENT_LIST_DIR}/sgns-blockstoreTargets.cmake" )
```

**7d. `thirdparty/build/CommonTargets.cmake`** — sgns-blockstore entry (863–920). Two edits: (1) `-Dipfs-lite-cpp_DIR:PATH=${_FINDPACKAGE_IPFS_LITE_CONFIG_DIR}` among the cache args (variable already defined at line 530 by the ipfs-lite-cpp entry; hint-usage precedent = ipfs-pubsub entry, lines ~551–552); (2) `DEPENDS libp2p rocksdb minio-cpp` → append `ipfs-lite-cpp`. **Landmine:** `-DTESTING:BOOL=ON` must remain the LAST cache arg (entry comment at ~910–919 documents why); insert the new `-D` before it, never after:

```cmake
    -DCMAKE_FIND_PACKAGE_PREFER_CONFIG:BOOL=OFF
    -DTESTING:BOOL=ON
    DEPENDS libp2p rocksdb minio-cpp
```

**7e. `test/CMakeLists.txt`** — registration analog (1–7); every new in-tree test follows `addtest` + LABELS (the `tier1_static_audit` ctest at 224–226 fails the lane on an unlabeled registration — D-14):

```cmake
addtest(memory_block_store_test memory_block_store_test.cpp)
target_link_libraries(memory_block_store_test
    sgns-blockstore
    p2p::p2p_cid
)
set_tests_properties(memory_block_store_test PROPERTIES LABELS "Tier1")
```

Script-mode `add_test` precedent for the consumer-proof driver (216–218):

```cmake
add_test(NAME header_hygiene
    COMMAND ${CMAKE_COMMAND} -DSRC_DIR=${CMAKE_SOURCE_DIR} -P ${CMAKE_CURRENT_SOURCE_DIR}/header_hygiene_check.cmake)
set_tests_properties(header_hygiene PROPERTIES LABELS "Tier1")
```

---

### 8. Out-of-tree consumer project **CREATED** (`test/out_of_tree_consumer/`)

**Partial analog:** the library's own root `CMakeLists.txt` (find_package + target_link_libraries consumer side) and the registration pattern in §7e. No tracked standalone-consumer project exists in the repo — mechanics come from RESEARCH.md Q8/Q9: own `CMakeLists.txt` with `find_package(sgns-blockstore CONFIG REQUIRED)` + `*_DIR` hints (`sgns-blockstore_DIR`, `libp2p_DIR`, `RocksDB_DIR`, `miniocpp_DIR`, `httplib_DIR`, `nlohmann_json_DIR`, `pugixml_DIR`, `ipfs-lite-cpp_DIR` pointing at `thirdparty/build/Windows/Debug/...` install trees), one TU constructing `S3ClientConfig{...}` + `OpenMinioS3Client(...)` (construct-only against a dead endpoint IS the D-06 no-I/O proof), driven by an outer script-mode `add_test` (`header_hygiene` precedent above) with `LABELS "Tier1"`. Prior art to inspect (NOT a citable analog — untracked build artifact): `thirdparty/build/Windows/Debug/sgns-blockstore-smoke/`.

---

### 9. Cross-check evidence artifact **CREATED** (`docs/evidence/blake2b-crosscheck/getcidof-crosscheck.log`)

**Analog (committed-evidence location/format):** `thirdparty/sgns-blockstore/docs/evidence/s3d-spike/` (tracked: README.md + capture .txt files — per-topic directory, human-readable, diffable, no secrets). **Analog (dev-run log shape):** `.planning/workstreams/rocksdb-backup/milestones/v1.0-phases/03-minio-cpp-integration-s3client-adapter/03-04-live-run-evidence.log` — command lines + output tails + a dated resumption section (`2026-10-21 RESUMPTION RUN - G-3-1 CLOSED (user-approved option (a))` at line 136). Suggested per-payload content (RESEARCH Q4): payload hex, blake2b-256 hex (Python source B), library 3-arg `CidOf` string, `getCidOf` string, agreement verdict. **Format note:** the precedent log is UTF-16LE (a PowerShell-redirect artifact) — write the new artifact as plain UTF-8 so it diffs cleanly. The generating dev TU (calls `sgns::common::getCidOf` against the superbuild install tree) is throwaway — only the log is committed.

## Shared Patterns

### Result envelope + explicit failure mapping
**Source:** `include/sgns-blockstore/Cid.hpp:33-44` (library-local `result<R,S,policy::terminate>` alias) + the verify-site comment in every backend (`MemoryBlockStore.cpp` ~66-69): `CidOf` carries `std::error_code`, so its failure is **mapped explicitly, never OUTCOME_TRY'd** across the BlockStatus-typed envelope. Guard with `has_value()`/`if (!res)` before `.value()` — `.value()` on failure terminates.
**Apply to:** the 3-arg `CidOf` (same default error type), `OpenMinioS3Client` wrapper (map `BlockStatus` errors through `if (!opened) return opened.error();`).

### Throw-at-entry programmer-error contract
**Source:** the three `ValidateCidHash` gates + `MinioS3Client::Open` (empty endpoint/bucket) + `S3BlockStore::Open` (null client/empty prefix).
**Shape:** `throw std::invalid_argument("sgns::blockstore: <what> - <why/decision-ID>");` — message prefix + decision-ID citation is house style.
**Apply to:** 3-arg `CidOf` unsupported-hash throw; `OpenMinioS3Client` config validation (keep-throw per precedent); widened gate message.

### Doxygen + decision-ID comment style (Coding Standards binding)
**Source:** every public header read this session — `@brief`/`@param`/`@return`/`@note` on all public interfaces, with decision IDs (D-xx, SC-x, BACK-xx, T-3-xx) woven into prose; Ullman braces, 4-space indent inside namespaces, PascalCase types/headers (`Cid.hpp`, `S3Client.hpp`), trailing-underscore members (`storage_`, `keyPrefix_`, `client_`, `impl_`, `fault_`), header guards `SGNS_BLOCKSTORE_*_HPP`.
**Apply to:** the new `CidOf` overload doc block (rewrite the `@note`), the `OpenMinioS3Client` doc block (add D-06 contract), any new internal helper headers.

### Test doc convention
**Source:** every test file — `@given/@when/@then` block above each TEST_F, named decision contracts in assertions.
**Apply to:** all new/retargeted vector, roundtrip, rejection, and consumer tests.

### Tier-1 fail-closed registration
**Source:** `test/CMakeLists.txt` (every `addtest` + `set_tests_properties(... LABELS "Tier1")`; `tier1_static_audit` trips on unlabeled registrations) + `docs/testing-tiers.md` (CI lane: `ctest --test-dir <sub-build> -C Debug --output-on-failure -L Tier1 --no-tests=error`).
**Apply to:** the out-of-tree consumer test (D-08: Tier-1 hermetic, zero network) and any new kit-instantiated binaries.

### Known-vector two-source pinning discipline (D-02)
**Source:** `test/cid_spike_test.cpp:66-73` (the transcription-error provenance comment).
**Apply to:** every blake2b/DAG_CBOR literal pinned in the kit — RFC 7693/KAT (source A) + Python `hashlib.blake2b(digest_size=32)` (source B) must agree before pinning; the committed cross-check log is the third bridge to the real producer.

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `test/out_of_tree_consumer/CMakeLists.txt` + TU | test (standalone consumer) | request-response | No tracked standalone-consumer CMake project exists anywhere in the repo. Closest tracked material: the library's own root `CMakeLists.txt` (find_package consumer side) + script-mode `add_test` driver precedent. `thirdparty/build/Windows/Debug/sgns-blockstore-smoke/` is prior art but an **untracked build artifact** — inspect for ideas, never cite as analog (gate #3645). Planner should follow RESEARCH.md Q8/Q9 mechanics verbatim. |
| throwaway `getCidOf` cross-check dev TU | utility (dev-run, never committed) | transform | Deliberately has no analog and leaves none — only its output log (`docs/evidence/blake2b-crosscheck/`) is committed, following the s3d-spike evidence precedent. |

## Metadata

**Analog search scope:** `thirdparty/sgns-blockstore/` (include, src, test, cmake, docs), `thirdparty/ipfs-lite-cpp/` (crypto/blake2, primitives/cid), `thirdparty/build/CommonTargets.cmake`, `.planning/workstreams/rocksdb-backup/milestones/v1.0-phases/03-*/`
**Files scanned:** ~25 (all tracked-verified via `git ls-files` in the owning submodule/repo)
**Pattern extraction date:** 2026-10-22
**Line-number caveat:** ranges verified against the tree this session; minor ±3 drift possible on mid-function sites (verify with the excerpt text, not bare line numbers, when writing plans).
