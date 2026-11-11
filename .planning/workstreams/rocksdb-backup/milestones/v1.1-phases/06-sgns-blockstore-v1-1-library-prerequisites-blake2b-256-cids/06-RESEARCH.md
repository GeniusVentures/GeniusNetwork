# Phase 6: sgns-blockstore v1.1 Library Prerequisites — blake2b-256 CIDs & Installed S3 Client Factory - Research

**Researched:** 2026-10-22
**Domain:** C++17 library widening (multihash gate, CID construction, CMake install/package config) in `thirdparty/sgns-blockstore`
**Confidence:** HIGH (all code claims read from the tree this session; only external test-vector literals are lower-confidence and every one carries a mandatory re-derivation step)

## Summary

The v1.0 library gates every op on `cid.content_address.getType() != libp2p::multi::HashType::sha256` at three duplicated anonymous-namespace `ValidateCidHash` sites (Memory `src/MemoryBlockStore.cpp:23`, Local `src/LocalBlockStore.cpp:35`, S3 `src/S3BlockStore.cpp:27`), and every verify-on-put/get re-hashes via the 2-arg `CidOf(bytes, codec)` which is sha-256-hardcoded. **The critical research finding: the pinned `thirdparty/libp2p` tree has NO blake2b hasher** — only `crypto/sha/sha256.hpp` and `sha512.hpp` exist; `blake2b_256 = 0xb220` is only an enum value in `multi/hash_type.hpp:22`. The blake2b implementation the whole SuperGenius ecosystem actually uses — including the real CRDT producer `sgns::common::getCidOf` — is the vendored RFC 7693 reference C code in `thirdparty/ipfs-lite-cpp/crypto/blake2/`, exported as the CMake target `ipfs-lite-cpp::blake2` (links only `ipfs-lite-cpp::blob` + `ipfs-lite-cpp::outcome`). This is the D-10 contingency the CONTEXT's discretion list delegated to the researcher: **link `ipfs-lite-cpp::blake2`, do not wait for a libp2p API that does not exist**. It guarantees byte-compatibility with `getCidOf` by construction (same object code), and avoids a duplicate-symbol link landmine in Phase 7.

For LIB-02, the shipped package config (`cmake/config.cmake.in`) does only `find_dependency(RocksDB CONFIG)` while the exported target `sgns-blockstore::sgns-blockstore` carries `INTERFACE_LINK_LIBRARIES "p2p::p2p_cid;RocksDB::rocksdb;$<LINK_ONLY:miniocpp::miniocpp>"` — so today an out-of-tree `find_package(sgns-blockstore CONFIG REQUIRED)` consumer cannot configure: three imported targets are missing. This is exactly the gap D-07 hardens "as forced": `find_dependency(libp2p CONFIG)` + `find_dependency(miniocpp CONFIG)` (whose own consumer config re-runs `miniocpp-deps.cmake`, requiring OpenSSL/ZLIB/nlohmann_json/httplib/pugixml resolvable in the consumer's context), plus `find_dependency(ipfs-lite-cpp CONFIG)` once Wave 1 adds the blake2 link. All required package configs exist in the superbuild install tree at `thirdparty/build/Windows/Debug/<pkg>/lib/cmake/<pkg>`.

**Primary recommendation:** Wave 1 = link `ipfs-lite-cpp::blake2` (PRIVATE) + 3-arg `CidOf` overload + widen the three gates to `{sha256, blake2b_256}` + branch all six verify sites on the CID's own multihash + `dag-cbor` codec token + conformance/guard retarget (sha-512 exemplar) + superbuild entry gains `ipfs-lite-cpp_DIR`/DEPENDS. Wave 2 = `OpenMinioS3Client(const S3ClientConfig&)` free function declared in installed `S3Client.hpp`, defined in a src TU seeing `MinioS3Client.hpp`; standalone consumer CMake project under `test/` (Tier-1 ctest) drives the config.cmake.in hardening exactly as its failures force.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** The gate widens to **exactly the pair {sha-256, blake2b-256}** — hard accepted set, verification explicitly branches on both hashes; no allowlist machinery, no general multihash dispatch. Matches Phase-1 D-08's additive-widening posture: the next widening (if ever needed) is another additive change — **Reversibility:** costly — the conformance kit, guard tests, and both verification branches bind the accepted set; narrowing after SC3's no-break bar is published would be an API break
- **D-02:** Conformance vectors are **independently derived AND cross-checked**: pin literals derived from an independent source (RFC 7693 blake2b test vectors / IPLD DAG_CBOR fixtures), and additionally cross-check once against real `sgns::common::getCidOf` output via a **committed dev-run artifact** (no library→SuperGenius dependency — the cross-check is evidence, not a linked test). The compatibility claim with the actual CRDT CID producer is thereby evidenced, not trusted
- **D-03:** Hashes still outside the accepted set (e.g. sha-512) keep the **`std::invalid_argument` throw-at-entry** programmer-error contract — the D-08 posture is unchanged, only the accepted set grew. Existing blake2b-*rejection* guard tests re-target a still-out-of-set hash — **Reversibility:** one-way — the throw contract is the published v1.0 API behavior SC3 exists to protect
- **D-04:** blake2b capability surfaces as a **3-arg overload `CidOf(bytes, codec, HashType)`** — a new symbol; the existing 2-arg signature stays literally untouched (delegates to sha-256). An unsupported `HashType` argument throws `invalid_argument` (D-03 posture). Most literal reading of SC3's no-break bar — **Reversibility:** costly — published installed-helper surface; once consumers (tests, Phase 7+ adapters) call the 3-arg form, removing it is an API break
- **D-05:** `OpenMinioS3Client(const S3ClientConfig&)` returns **`result<std::shared_ptr<S3Client>, BlockStatus>`** — envelope-consistent with every `Open()` in the library (`MinioS3Client::Open`, `S3BlockStore::Open`, `LocalBlockStore::Open` precedents), interface-typed so the installed header stays SDK-free, and injects straight into `S3BlockStore::Open(std::shared_ptr<S3Client>, ...)`. Implementation is a thin wrapper over the internal `MinioS3Client::Open`; `MinioS3Client.hpp` stays uninstalled — **Reversibility:** costly — the published factory signature is what SC4's out-of-tree consumer proof compiles against
- **D-06:** Construction is **eager config validation, zero network I/O** — validate endpoint/bucket/port/path-style at the factory call (bad config fails AT the call site, dodging the BaseUrl-snapshot landmine: port/virtual-style must be right before client init); the minio client is lazy, so connection failures surface later through the op taxonomy, never at construction — **Reversibility:** costly — documented construction contract; consumers will rely on no-I/O-at-construction for startup ordering
- **D-07:** **Prove first, harden as forced:** build the SC4 out-of-tree consumer proof first; harden `cmake/config.cmake.in` exactly as far as the proof forces (transitive miniocpp/httplib/nlohmann_json/pugixml `find_dependency` resolution); anything the minimal consumer doesn't need defers to Phase 7's real `CommonBuildParameters.cmake` consumption. Evidence-driven — the Phase-3 D-10/D-05 no-pre-committed-contingency posture
- **D-08:** The proof runs as a **Tier-1 hermetic ctest**: a standalone CMake project under `test/` (its own `CMakeLists.txt` doing `find_package(sgns-blockstore CONFIG REQUIRED)` against the install tree), compile+link+construct only, zero network, registered with a Tier-1 label in the fail-closed lane — **Reversibility:** costly — the CI lane, tier label, and consumer-project shape bind together (v1.0 tier discipline)

### the agent's Discretion
- Which still-rejected hash becomes the guard-test exemplar (e.g. sha-512) and the guard-test rewrite mechanics
- The blake2b implementation entry point (libp2p crypto blake2 API shape at the pinned tree) — researcher confirms; any missing-API contingency decided on evidence per D-10 posture
- Whether the three duplicated per-backend throw-site checks consolidate into one shared validate helper (`S3BlockStore.hpp:163` already references a `ValidateCidHash` name) — planner's call
- Conformance-kit vector-set composition beyond the SC1 letter (payload diversity, DAG_CBOR fixture choices)
- Exact placement/wording of the factory declaration in `S3Client.hpp` (Doxygen per Coding Standards)
- The out-of-tree consumer project's name/location under `test/` and its CMake mechanics (how the install tree is pointed at)
- The `dag-cbor` codec token is a new `CodecToken()` switch case (SC2's observable); the `unknown-codec` catch-all stays as-is

### Deferred Ideas (OUT OF SCOPE)
- `2026-08-10-fix-vulkan-capability-probe-deadlock-in-processingmanager-cr.md` — unrelated backlog todo; ignore completely.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| LIB-01 | blake2b-256 CIDv1 blocks accepted additively alongside sha-256 (hash-gate widening, verify-on-put/get against the CID's own multihash, known DAG_CBOR/blake2b vectors, conformance kit + guard tests extended, `dag-cbor` S3 key token, no public-API break) | Q1 (blake2b entry point + `getCidOf` ground truth), Q2 (three gate sites), Q3 (kit + rejection tests to flip), Q4 (vector derivation + D-02 cross-check artifact), Q5 (six verify sites), Q6 (CodecToken + DAG_CBOR=0x71), Q10 (hygiene guard) |
| LIB-02 | Installed factory `OpenMinioS3Client(S3ClientConfig)` in installed `S3Client.hpp`; out-of-tree consumer constructs the production client linking only `sgns-blockstore::sgns-blockstore` from the install tree | Q7 (S3Client.hpp surface + MinioS3Client::Open precedent + eager-validation surface), Q8 (install rules + config.cmake.in gaps the proof forces), Q9 (Tier-1 ctest mechanics + tier1_static_audit D-14 registration guard) |
</phase_requirements>

## Project Constraints (from workspace conventions)

- `Coding Standards.md`: Ullman braces, PascalCase types/headers, `m_`/trailing-underscore members, Doxygen (`@brief`/`@param`/`@return`/`@note`) on all public interfaces. Existing library code follows this exactly — new declarations must too.
- Library-only phase: no SuperGenius/GeniusSDK source changes. The one build-orchestration file outside `thirdparty/sgns-blockstore/` that MUST change is `thirdparty/build/CommonTargets.cmake` (the sgns-blockstore ExternalProject entry gains the ipfs-lite-cpp config-dir hint + DEPENDS) — the same file Phases 3–4 already extended (minio-cpp/pugixml/json entries). This is thirdparty superbuild wiring, not consumer source.
- Work inside `thirdparty/sgns-blockstore` read-only during research (done); implementation edits are the executor's job.

---

## Q1 — blake2b entry point (CRITICAL): libp2p has none; ipfs-lite-cpp is the ecosystem's blake2b

**Finding: the pinned libp2p tree provides NO blake2b hashing capability.** [VERIFIED: directory listing + grep this session]

- `thirdparty/libp2p/include/libp2p/crypto/` contains exactly two hashers, both sha-family [VERIFIED: directory listing]:
  ```
  crypto/sha/sha256.hpp
  crypto/sha/sha512.hpp
  ```
- A recursive grep for `blake2` across `thirdparty/libp2p/` hits only `include/libp2p/multi/hash_type.hpp` and `test/libp2p/multi/multihash_test.cpp` [VERIFIED: grep this session — 10 matches, 2 files].
- The enum value exists and is the one to accept [VERIFIED: thirdparty/libp2p/include/libp2p/multi/hash_type.hpp:14-27, quoted verbatim]:
  ```cpp
  enum HashType : uint64_t {
    identity = 0x0,
    sha1 = 0x11,
    sha256 = 0x12,
    sha512 = 0x13,
    blake2b_256 = 0xb220,
    blake2s128 = 0xb250,
    blake2s256 = 0xb260,
    sha2_256_trunc254_padded = 0x1012,
    poseidon_bls12_381_a1_fc1 = 0xb401,
  };
  ```

**The implementation the SuperGenius ecosystem actually uses** (including the real CRDT CID producer): vendored RFC 7693 reference C code in `thirdparty/ipfs-lite-cpp/crypto/blake2/` (`blake2b.c`, `blake2b.h`, `blake2b160.cpp`), exposed as:

- `sgns::crypto::blake2b::blake2b_256(gsl::span<const uint8_t>) -> Blake2b256Hash` where `Blake2b256Hash = common::Blob<32>` [VERIFIED: thirdparty/ipfs-lite-cpp/crypto/blake2/blake2b160.hpp:10-32, quoted verbatim]:
  ```cpp
  namespace sgns::crypto::blake2b
  {
      const size_t BLAKE2B256_HASH_LENGTH = 32; // 256 BIT
      using Blake2b256Hash = common::Blob<BLAKE2B256_HASH_LENGTH>;
      /**
       * @brief Get blake2b-256 hash
       * @param to_hash - data to hash
       * @return hash
       */
      Blake2b256Hash blake2b_256( gsl::span<const uint8_t> to_hash );
  }
  ```
- Implementation [VERIFIED: thirdparty/ipfs-lite-cpp/crypto/blake2/blake2b160.cpp:18-25]:
  ```cpp
  Blake2b256Hash blake2b_256( gsl::span<const uint8_t> to_hash )
  {
      Blake2b256Hash res{};
      ::sgns_blake2b( res.data(), BLAKE2B256_HASH_LENGTH, nullptr, 0, to_hash.data(), to_hash.size() );
      return res;
  }
  ```
- CMake: `add_library(blake2 blake2s.c blake2b.c blake2b160.cpp)` linking `blob` + `outcome` [VERIFIED: thirdparty/ipfs-lite-cpp/crypto/blake2/CMakeLists.txt:1-7]; exported in the package config with namespace `ipfs-lite-cpp::` [VERIFIED: thirdparty/ipfs-lite-cpp/CMakeLists.txt:60-78 — `install(TARGETS ... blake2 ... EXPORT ipfs-lite-cppConfig)`; `NAMESPACE ipfs-lite-cpp::`]. The installed imported target is `ipfs-lite-cpp::blake2` with `INTERFACE_LINK_LIBRARIES "ipfs-lite-cpp::blob;ipfs-lite-cpp::outcome"` — both in the same export set, no other find_dependency needed [VERIFIED: thirdparty/build/Windows/Debug/ipfs-lite-cpp/lib/cmake/ipfs-lite-cpp/ipfs-lite-cppConfig.cmake lines 170-174, read this session].

**The real CRDT producer (`sgns::common::getCidOf`) — the shape every widening must match** [VERIFIED: thirdparty/ipfs-lite-cpp/primitives/cid/cid.cpp:128-136, quoted verbatim — note it is NOT in SuperGenius/src; it lives in the ipfs-lite-cpp submodule]:
```cpp
namespace sgns::common
{
    IPFS::outcome::result<CID> getCidOf( gsl::span<const uint8_t> bytes )
    {
        auto hash_raw = crypto::blake2b::blake2b_256( bytes );
        BOOST_OUTCOME_TRY( auto hash, Multihash::create( HashType::blake2b_256, hash_raw ) );
        return CID( CID::Version::V1, CID::Multicodec::DAG_CBOR, hash );
    }
}
```
So the exact target shape is **CIDv1 + DAG_CBOR + blake2b-256** via the same three-step composition the library already uses.

**How `src/Cid.cpp` does sha-256 today (the pattern to mirror)** [VERIFIED: thirdparty/sgns-blockstore/src/Cid.cpp:19-31, quoted verbatim]:
```cpp
outcome::result<Cid> CidOf(gsl::span<const uint8_t> bytes,
                           libp2p::multi::MulticodecType::Code codec)
{
    OUTCOME_TRY(digest, libp2p::crypto::sha256(bytes));
    OUTCOME_TRY(hash,
                libp2p::multi::Multihash::create(
                    libp2p::multi::HashType::sha256,
                    gsl::span<const uint8_t>(digest.data(), digest.size())));
    return Cid(Cid::Version::V1, codec, std::move(hash));
}
```
`libp2p::crypto::sha256` signature for reference [VERIFIED: thirdparty/libp2p/include/libp2p/crypto/sha/sha256.hpp:44-46]: `outcome::result<libp2p::common::Hash256> sha256(gsl::span<const uint8_t> input);` (free function).

**Researcher-confirmed contingency (D-10 posture, within CONTEXT discretion):** sgns-blockstore gains `find_package(ipfs-lite-cpp CONFIG REQUIRED)` and links `ipfs-lite-cpp::blake2` **PRIVATE** (no installed header mentions blake2 — hygiene stays green; it appears in the export as `$<LINK_ONLY:ipfs-lite-cpp::blake2>`, forcing `find_dependency(ipfs-lite-cpp CONFIG)` into config.cmake.in during Wave 2's proof). The superbuild entry (`thirdparty/build/CommonTargets.cmake:863-920`) gains `-Dipfs-lite-cpp_DIR:PATH=${_FINDPACKAGE_IPFS_LITE_CONFIG_DIR}` (variable already defined at line 530) and `DEPENDS` gains `ipfs-lite-cpp` (ExternalProject already defined at line 498). Byte-compatibility with `getCidOf` is by construction — same object code. The rejected alternative (vendor a second copy of the reference `blake2b.c` into sgns-blockstore) is a Phase-7 link landmine: ipfs-lite's copy exports **unrenamed globals** `blake2b_init`/`blake2b_update`/`blake2b_final` [VERIFIED: thirdparty/ipfs-lite-cpp/crypto/blake2/blake2b.h:31-56 — only the all-in-one is renamed to `sgns_blake2b`]; two static archives both pulled into SuperGenius's link would collide unless the copy renamed every symbol.

## Q2 — The three throw-site gates (exact quotes + line numbers)

Three byte-identical anonymous-namespace free functions, one per backend TU:

1. **Memory** [VERIFIED: thirdparty/sgns-blockstore/src/MemoryBlockStore.cpp:23-33]:
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
2. **Local** [VERIFIED: thirdparty/sgns-blockstore/src/LocalBlockStore.cpp:35-45] — doc comment says "Verbatim from the MemoryBlockStore reference backend"; identical body, throw at line 39.
3. **S3** [VERIFIED: thirdparty/sgns-blockstore/src/S3BlockStore.cpp:27-37] — identical body, throw at line 32.

Each is invoked at the top of every public op (`Put`, `Get`, `Has`, `GetSize`) and once per element in the **PutMany pre-validation loop** before any write [VERIFIED this session]: `MemoryBlockStore.cpp:157`, `LocalBlockStore.cpp:532`, `S3BlockStore.cpp:244` — all three read `ValidateCidHash(input.cid);` inside a `for (const auto& input : blocks)` batch pre-pass (D-14 no-partial-writes contract).

**The `S3BlockStore.hpp:163` reference** is `DeriveKey`'s doc comment [VERIFIED: thirdparty/sgns-blockstore/include/sgns-blockstore/S3BlockStore.hpp:160-166]:
```cpp
/**
 * @brief The ONE key-derivation place (BACK-07 layout).
 * @param cid a sha256-gated CID (ValidateCidHash ran first)
 * @return <keyPrefix>/<codec>/<xx>/<cid-string>, or a Corrupt
 *         failure when the CID cannot be rendered (practically
 *         unreachable for sha256 CIDv1/v0 - defensive mapping)
 */
```
**Consolidation is natural and cheap:** the three bodies are identical; a single internal (src/, never installed) header — e.g. `src/CidGate.hpp` — with one `ValidateAcceptedHash(const Cid&)` used by all three TUs removes triplicated message strings (the message text itself names "sha-256 only" and MUST change once, not three times). Planner's call per discretion; the throw contract (D-03) is unchanged either way.

## Q3 — Conformance kit current shape; what flips; the re-target exemplar

**The kit** (`thirdparty/sgns-blockstore/test/conformance/BlockStoreConformanceTests.hpp`, never installed, macro `SGNS_BLOCKSTORE_CONFORMANCE_TESTS(SuiteName, factory)`) contains:

- `MakeCid(payload)` — sha-256 CIDv1 RAW via `CidOf` [VERIFIED: BlockStoreConformanceTests.hpp:45-50].
- **`MakeBlake2bCid()` — already exists, and is the rejection probe to convert** [VERIFIED: BlockStoreConformanceTests.hpp:52-67, quoted verbatim]:
  ```cpp
  inline Cid MakeBlake2bCid()
  {
      // The CRDT CBOR boundary shape that must throw at API entry (D-08).
      static const uint8_t digest[32] = {
          0xb1, 0xb2, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
          0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0x10,
          0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18,
          0x19, 0x1a, 0x1b, 0x1c, 0x1d, 0x1e, 0x1f, 0x20,
      };
      return Cid(Cid::Version::V1, libp2p::multi::MulticodecType::Code::RAW,
                 libp2p::multi::Multihash::create(
                     libp2p::multi::HashType::blake2b_256,
                     gsl::span<const uint8_t>(digest, 32))
                     .value());
  }
  ```
  Note: it uses a **fake digest** and the **RAW codec** — the CRDT shape is DAG_CBOR. The widened roundtrip vectors (Q4) should construct real-digest DAG_CBOR CIDs; the fake-digest helper's remaining use is as a *no-payload* gate probe (Put with bytes that cannot hash to it → still Corrupt, and Has/GetSize gate-throw paths that never hash).
- The blake2b-REJECTION kit tests that flip to roundtrip/rejection-retarget (all instantiated 3× via the macro — Memory, Local, S3) [VERIFIED: BlockStoreConformanceTests.hpp:195-251]:
  - `PutNonSha256HashThrowsInvalidArgument` (line 195)
  - `GetNonSha256HashThrowsInvalidArgument` (line 203)
  - `PutManyInvalidHashTypeThrowsBeforeAnyWrite` (line 237)
- Per-backend rejection tests to re-target [VERIFIED this session]:
  - `memory_block_store_test.cpp:197` `Blake2bCidThrowsInvalidArgument` (Put/Get/Has/PutMany all EXPECT_THROW) and `:340` `PutManyBlake2bThrowsAndWritesNothing` (asserts nothing written)
  - `local_block_store_test.cpp` — `Blake2bCid()` helper at lines 62-79 (fake digest, RAW codec); rejection assertions at lines 490-492 (`MarkUploadedDurable(Blake2bCid())` / `GetUploadState(Blake2bCid())` EXPECT_THROW — these journal-tooling gates widen too or stay throwers per D-03 depending on chosen semantics; they call the same store gate, so they widen with it)
  - `s3_block_store_test.cpp` — no standalone blake2b test; it rides the conformance macro (`S3BlockStoreConformance`, instantiated at lines 496-506)

**Re-target exemplar (discretion — recommendation): sha-512.** `HashType::sha512 = 0x13` [VERIFIED: hash_type.hpp:18, quoted in Q1], 64-byte digest fits `Multihash::kMaxHashLength = 127` [VERIFIED: thirdparty/libp2p/include/libp2p/multi/multihash.hpp:35] so `Multihash::create` succeeds and the *gate* (not the multihash ctor) is provably what throws — exactly the D-03 programmer-error shape. Construction mirrors `MakeBlake2bCid()` with a 64-byte fake digest. (Alternative: `blake2s128 = 0xb250` keeps the "blake2" flavor but confuses the narrative — sha-512 is the CONTEXT's own example.)

**Existing sha-256 known-vector precedent** (the SC3 "pass unchanged" set) [VERIFIED: test/cid_spike_test.cpp:40,66-73; test/s3_block_store_test.cpp:57-97]:
- `"hello world"` → CIDv1 RAW sha-256 string `bafkreifzjut3te2nhyekklss27nh3k72ysco7y32koao5eei66wof36n5e` (cid_spike_test.cpp:73 — includes the recorded lesson that the research-doc constant once had a transcription error at position 33; the spike's cross-check discipline caught it. Wave 1's vector pinning MUST repeat that two-source discipline — D-02 exists for exactly this).
- S3 key layout vector: `v1/blocks/raw/b9/bafkreifzjut3te2nhyekklss27nh3k72ysco7y32koao5eei66wof36n5e` (s3_block_store_test.cpp:93-97), derived in-test from `ContentIdentifierCodec::toString` + first-digest-byte hex fan-out.

## Q4 — Known vectors: derivation procedure + the D-02 cross-check artifact

**Vector bar (D-02): independently derived AND cross-checked. Two independent sources, then one committed cross-check:**

1. **Independent source A — RFC 7693 / official BLAKE2 KAT** [CITED: https://www.rfc-editor.org/rfc/rfc7693 (BLAKE2 spec); https://github.com/BLAKE2/BLAKE2/tree/master/testvectors (blake2-kat.json official known-answer tests)]. The RFC appendix and the official KAT JSON are independent of the vendored C code the repo carries.
2. **Independent source B — Python stdlib on this workstation (verified available this session: Python 3.13.4)**: `hashlib.blake2b(data, digest_size=32)` is an RFC 7693-conformant independent implementation. Derivation one-liner the plan can pin verbatim:
   ```
   python -c "import hashlib;print(hashlib.blake2b(b'<payload>',digest_size=32).hexdigest())"
   ```
   Literals are only pinned when A and B agree. (Known empty-input value circulating widely — `blake2b-256("") = 0e5751c026e543b2e8ab2eb06099daa1d1e5df47778f7787faab45cdf12fe3a8` — is [ASSUMED] from training memory; re-derive with source B before pinning, per the cid_spike_test.cpp:66-72 transcription-error precedent.)
3. **DAG_CBOR payload choices (discretion — recommendation): hand-derivable per RFC 8949 canonical CBOR** [CITED: https://www.rfc-editor.org/rfc/rfc8949], so payload bytes themselves are independently derivable without any tooling:
   - `{}` → `a0` (1 byte)
   - `{"key": 1}` → `a1 63 6b 65 79 01` (6 bytes)
   - `{"hello": "world"}` → `a1 65 68 65 6c 6c 6f 65 77 6f 72 6c 64` (13 bytes)
   Payload diversity beyond this (e.g. an array, a nested map) is optional breadth per discretion.
4. **CID string derivation** for the pinned assertions: CIDv1 wire bytes = `0x01` (version) + `0x71` (DAG_CBOR, Q6) + multihash `varint(0xb220) || 0x20 || digest32`, base32-lower-no-padding with multibase prefix `b` [CITED: https://github.com/multiformats/multibase (base32); https://github.com/multiformats/multicodec (blake2b-256 = 0xb220, dag-cbor = 0x71)]. By in-session arithmetic varint(0xb220) = `a0 e4 02` [ASSUMED — arithmetic derivation; verify in the dev script before pinning: `python -c "v=0xb220;print([hex(b) for b in iter(lambda:[v&0x7f],[None])][0] if False else [])"` or simply trust the library's `UVarint` in a scratch check — the pinned CID *string* must come from the cross-check run anyway]. DAG_CBOR+blake2b-256 CIDv1 strings characteristically start `bafyre...` (vs RAW+sha-256's `bafkrei...`) [ASSUMED — pattern observation, verify at derivation time].

**D-02 committed cross-check artifact — how to produce it (dev-run, no library→SuperGenius link):**

- Ground truth source: `sgns::common::getCidOf` at `thirdparty/ipfs-lite-cpp/primitives/cid/cid.cpp:129` (declared `primitives/cid/cid.hpp:85-87`). A throwaway dev TU (never committed as library/test source; only its output log is committed) calls it for each chosen vector payload and prints `getCidOf(bytes).value().toString().value()`.
- Build/link: against the **superbuild install tree** — headers at `thirdparty/build/Windows/Debug/ipfs-lite-cpp/include`, link `ipfs-lite-cpp::cid` whose installed interface is `INTERFACE_LINK_LIBRARIES "Boost::boost;ipfs-lite-cpp::blake2;p2p::p2p_cid;c-ares::cares;soralog::soralog;fmt::fmt"` [VERIFIED: ipfs-lite-cppConfig.cmake, target `ipfs-lite-cpp::cid`, read this session]. So the dev CMake needs `-Dipfs-lite-cpp_DIR`, `-Dlibp2p_DIR`, plus `c-ares`/`soralog`/`fmt`/`Boost` hints — mirror the ipfs-pubsub entry's hint set [VERIFIED: thirdparty/build/CommonTargets.cmake:545-562 shows exactly this pattern of `-Dipfs-lite-cpp_DIR ... -Dlibp2p_DIR ...`].
- Alternatively (lighter): the same dev TU can call `sgns::crypto::blake2b::blake2b_256` + libp2p `Multihash::create` + `ContentIdentifier` to prove the *composition* — but the stronger, preferred evidence calls `getCidOf` itself (the real producer), per D-02's "the compatibility claim with the actual CRDT CID producer is thereby evidenced".
- Artifact placement: `thirdparty/sgns-blockstore/docs/evidence/` (existing committed-evidence precedent: `docs/evidence/s3d-spike/*` [VERIFIED: directory listing this session]; log format follows the `03-04-live-run-evidence.log` precedent — human-readable, diffable, no secrets). Suggested: `docs/evidence/blake2b-crosscheck/getcidof-crosscheck.log` containing per-payload: payload hex, blake2b-256 hex (source B), library `CidOf` 3-arg output string, `getCidOf` output string, agreement verdict. The conformance test then pins the literals; the log is the "evidenced, not trusted" bridge.

## Q5 — Verify-on-put/get hashing today (the six sites that must branch)

All six re-hash with the 2-arg (sha-256) `CidOf` and compare `computed.value() == cid` — so even if the gate were widened alone, a blake2b CID would fail Put as `Corrupt` (bytes can never hash to a blake2b CID under sha-256 recompute). Exact sites [VERIFIED: Select-String `auto computed = CidOf` this session]:

| Backend | Put verify | Get verify (options.verify) |
|---|---|---|
| Memory | `MemoryBlockStore.cpp:71` | `MemoryBlockStore.cpp:108` |
| Local | `LocalBlockStore.cpp:305` | `LocalBlockStore.cpp:427` |
| S3 | `S3BlockStore.cpp:124` | `S3BlockStore.cpp:177` |

Representative shape (S3 Put) [VERIFIED: thirdparty/sgns-blockstore/src/S3BlockStore.cpp:113-131]:
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
Get-verify attribution differs per backend: Memory → `BlockSource::Memory` ("stored bytes failed CID re-verification"), Local → `BlockSource::Local`, S3 → `BlockSource::Remote` ("fetched bytes failed CID re-verification") [VERIFIED: MemoryBlockStore.cpp:100-123; S3BlockStore.cpp:156-180, read this session]. This is SC2's "rejected as Corrupt with source attribution" — the widened byte-flip blake2b test asserts exactly these source enums (`BlockSource` values quoted in Planner inputs).

**Widening mechanics (D-01/D-04):** each site switches to the 3-arg overload passing the CID's own hash type — `CidOf(bytes, cid.content_type, cid.content_address.getType())` — so the recompute is sha-256 for sha-256 CIDs and blake2b-256 for blake2b CIDs (branch-on-own-multihash, no dispatch machinery). The `!computed` error-mapping branches and messages stay unchanged (the 3-arg form's unsupported-hash failure is unreachable here because the entry gate already threw — D-03 ordering).

## Q6 — CodecToken + key layout + DAG_CBOR constant

Current switch [VERIFIED: thirdparty/sgns-blockstore/src/S3BlockStore.cpp:42-53, quoted verbatim]:
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
Widening = one new case `DAG_CBOR → "dag-cbor"` (display-only; `unknown-codec` catch-all untouched per discretion). `DAG_CBOR = 0x71` is available in the pinned libp2p enum [VERIFIED: thirdparty/libp2p/include/libp2p/multi/multicodec_type.hpp:34, and `getName` already returns `"dag-cbor"` for it at :61-62]. Key derivation composes it at `S3BlockStore.cpp:110`: `keyPrefix_ + '/' + CodecToken(cid.content_type) + '/' + DigestFanoutByte(cid) + '/' + cid_string` — so a DAG_CBOR blake2b block lands at `v1/blocks/dag-cbor/<xx>/<bafyre...>`, observable via `InMemoryS3Client::ObjectKeys()` (s3_block_store_test.cpp:57-97 precedent). Note `DeriveKey`'s doc comment (Q2) says "practically unreachable for sha256" — `ContentIdentifierCodec::toString` handles DAG_CBOR CIDv1 (libp2p codec supports it; the `bafyr` prefix family) [ASSUMED — verify in the Wave-1 conformance run; if toString rejected DAG_CBOR the spike would have said so, but assert it in tests].

## Q7 — Installed `S3Client.hpp` surface + `MinioS3Client::Open` precedent + eager validation

**S3ClientConfig (the SDK-free config the factory takes)** [VERIFIED: thirdparty/sgns-blockstore/include/sgns-blockstore/S3Client.hpp:77-92, quoted verbatim]:
```cpp
struct S3ClientConfig
{
    std::string endpoint;         ///< host, e.g. "127.0.0.1"
    uint16_t port = 0;            ///< 0 = scheme default
    std::string region = "us-east-1";
    bool useTls = false;          ///< plain HTTP is the test-primary lane
    bool tlsVerify = true;        ///< NEVER default off (T-3-02)
    bool pathStyle = true;        ///< path-style addressing (no vhost)
    std::string accessKey;        ///< credential - never logged
    std::string secretKey;        ///< credential - never logged
    std::string bucket;           ///< target bucket (pre-provisioned)
};
```
(The `region` field carries an extra doc comment block in the file; fields/order as above.)

**The internal factory precedent** [VERIFIED: thirdparty/sgns-blockstore/src/MinioS3Client.hpp:52-56]:
```cpp
static result<std::unique_ptr<MinioS3Client>, BlockStatus> Open(
    const S3ClientConfig& config);
```
with the documented contract [VERIFIED: MinioS3Client.hpp:44-49]: "@throws std::invalid_argument on programmer error (empty endpoint or bucket)".

**What Open already validates eagerly vs. lazily** [VERIFIED: thirdparty/sgns-blockstore/src/MinioS3Client.cpp:137-150]:
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
- Eager today: endpoint/bucket non-empty check, then full `Impl` construction (BaseUrl + provider + client objects — all in-memory, **zero network I/O**; the minio client connects lazily per-op).
- The BaseUrl-snapshot landmine (D-06's motivating detail) [VERIFIED: MinioS3Client.cpp:96-136 — Impl member-order comment]: "base_url_ must be FULLY configured (port, virtual_style) BEFORE client_'s construction - the SDK snapshots the BaseUrl when the Client is built, so later field writes do not reach it". `MakeBaseUrl` sets `base_url.port = config.port; base_url.virtual_style = !config.pathStyle;` at :107-119.
- D-06's eager surface therefore: keep the existing empty endpoint/bucket throw; anything beyond (port is already `uint16_t`, path-style a bool — nothing to validate beyond emptiness) is documentation of the no-I/O contract in the factory's Doxygen rather than new checks. The planner decides whether to surface config errors as `result` failure vs. the existing throw — precedent (D-03 posture, `S3BlockStore::Open` at S3BlockStore.cpp:80-96 throws `invalid_argument` for null client/empty prefix) says **throw for programmer error**, keep `result` for runtime failures.

**Factory shape (D-05, locked):** free function in `sgns::blockstore` declared in installed `S3Client.hpp`:
```cpp
result<std::shared_ptr<S3Client>, BlockStatus> OpenMinioS3Client(
    const S3ClientConfig& config);
```
Defined in a src TU that includes the uninstalled `MinioS3Client.hpp` (e.g. `src/MinioS3Client.cpp` itself — no new TU needed): wrap `MinioS3Client::Open(config)` and convert `unique_ptr<MinioS3Client>` → `shared_ptr<S3Client>` (safe across the seam: `MinioS3Client`'s destructor is exported from the library, and `shared_ptr` type-erases the deleter, so the consumer never needs the complete type). `S3Client.hpp` already includes `Cid.hpp` (result alias) and declares `S3Client`/`S3ClientConfig` — the declaration needs **zero new includes** → hygiene (Q10) green by construction.

## Q8 — Install rules + config.cmake.in: the exact gaps D-07 hardens as forced

**Install rules** [VERIFIED: thirdparty/sgns-blockstore/CMakeLists.txt:60-84]:
- Headers: `install(DIRECTORY include/ ... FILES_MATCHING PATTERN "*.hpp")` — all 14 headers in `include/sgns-blockstore/` (listing this session: Block, BlockStatus, BlockStore, BlockStoreTooling, Capabilities, Cid, Durability, FaultController, LocalBlockStore, MemoryBlockStore, Options, S3BlockStore, S3Client, UploadDrainer). New `OpenMinioS3Client` declaration rides the existing rule; the 3-arg `CidOf` overload rides it too. **MinioS3Client.hpp stays in src/ (uninstalled)** — 04-CONTEXT boundary.
- Library: `install(TARGETS sgns-blockstore EXPORT sgns-blockstoreTargets ...)`; export namespace `sgns-blockstore::`; config dest `lib/cmake/sgns-blockstore`; version 1.0.0 `AnyNewerVersion`.

**Current config.cmake.in (complete file)** [VERIFIED: thirdparty/sgns-blockstore/cmake/config.cmake.in:1-6]:
```cmake
@PACKAGE_INIT@

include(CMakeFindDependencyMacro)
find_dependency(RocksDB CONFIG)

include ( "${CMAKE_CURRENT_LIST_DIR}/sgns-blockstoreTargets.cmake" )
```

**What the exported target actually requires** [VERIFIED: thirdparty/build/Windows/Debug/sgns-blockstore/lib/cmake/sgns-blockstore/sgns-blockstoreTargets.cmake, read this session]:
```cmake
set_target_properties(sgns-blockstore::sgns-blockstore PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES "${_IMPORT_PREFIX}/include"
  INTERFACE_LINK_LIBRARIES "p2p::p2p_cid;RocksDB::rocksdb;\$<LINK_ONLY:miniocpp::miniocpp>"
)
```
(plus, after Wave 1's PRIVATE blake2 link, `$<LINK_ONLY:ipfs-lite-cpp::blake2>` will append — same mechanism as miniocpp, since PRIVATE static-lib deps become LINK_ONLY entries.)

**The gaps, exactly:** a consumer doing `find_package(sgns-blockstore CONFIG REQUIRED)` + `target_link_libraries(x sgns-blockstore::sgns-blockstore)` fails at configure/generate unless `p2p::p2p_cid` and `miniocpp::miniocpp` (and post-Wave-1 `ipfs-lite-cpp::blake2`) already exist as targets. Forced hardening:
1. `find_dependency(libp2p CONFIG)` — package config at `thirdparty/build/Windows/Debug/libp2p/lib/cmake/libp2p` [VERIFIED: directory listing].
2. `find_dependency(miniocpp CONFIG)` — **caveat**: the installed `miniocpp-config.cmake` includes `miniocpp-deps.cmake` in the consumer's context [VERIFIED: thirdparty/build/Windows/Debug/minio-cpp/lib/cmake/miniocpp/miniocpp-config.cmake, read this session — `include("${CMAKE_CURRENT_LIST_DIR}/miniocpp-deps.cmake")`], and that script does `find_package(OpenSSL REQUIRED)`, `find_package(ZLIB REQUIRED)`, `find_package(nlohmann_json CONFIG REQUIRED)`, httplib (config→pkg-config→git-clone-source fallback, requires ≥0.51; pinned v0.53.1) and pugixml [VERIFIED: miniocpp-deps.cmake:20-50 read this session]. So the consumer needs `httplib_DIR`, `nlohmann_json_DIR`, `pugixml_DIR`, OpenSSL and ZLIB resolvable — the superbuild already documents exactly this re-run hazard in the sgns-blockstore entry's comment (CommonTargets.cmake:886-891) and the httplib QUIET-find trap (sgns-blockstore/CMakeLists.txt:35-44). The standalone consumer project must point `CMAKE_PREFIX_PATH`/`*_DIR` at the superbuild install trees; whether config.cmake.in can absorb any of this (it cannot absorb consumer-context `*_DIR`s) is why D-07 says "as forced": add the two/three `find_dependency` lines, and let the consumer's CMakeLists carry the `*_DIR` hints.
3. `find_dependency(ipfs-lite-cpp CONFIG)` (post-Wave-1, forced by the blake2 LINK_ONLY entry).
4. `find_dependency(RocksDB CONFIG)` already present.

**Does linking today's install tree transitively resolve miniocpp/httplib/nlohmann_json/pugixml?** No — nothing beyond RocksDB is found by the config; the static lib `sgns-blockstore.lib` needs the minio symbols at final link (LINK_ONLY), and miniocpp's own config then demands its dep chain. This is precisely what the SC4 proof surfaces on first run; D-07's order (proof first, then harden) means Wave 2's first task is the consumer + its expected-failure record, the second is the config.cmake.in edit that turns it green.

## Q9 — Build/test invocation (Windows developer workstation, verified layout)

- **Superbuild tree (VS generator):** `thirdparty/build/Windows/Debug/` — contains `sgns-blockstore.vcxproj`, `minio-cpp/`, `mcb/`, `pugixml/`, `json/`, `ipfs-lite-cpp/`, `sgns-blockstore/` [VERIFIED: directory listings this session]. (The `Release/` tree predates the sgns-blockstore entry — has no sgns-blockstore/minio-cpp dirs. Use Debug.)
- **sgns-blockstore sub-build (where ctest runs):** `thirdparty/build/Windows/Debug/sgns-blockstore/src/sgns-blockstore-build/` — contains `test_bin/`, `CTestTestfile.cmake`, per-test registrations with `LABELS "Tier1"` [VERIFIED: directory listing + CTestTestfile.cmake read this session].
- **Install tree (SC4 consumer target):** `thirdparty/build/Windows/Debug/sgns-blockstore/` → `include/`, `lib/sgns-blockstore.lib`, `lib/cmake/sgns-blockstore/sgns-blockstoreConfig.cmake` [VERIFIED: listings this session].
- **Tier-1 CI-faithful invocation** (from `docs/testing-tiers.md` §CI lane, with Windows config flag) [VERIFIED: thirdparty/sgns-blockstore/docs/testing-tiers.md:82-90]:
  ```
  ctest --test-dir thirdparty/build/Windows/Debug/sgns-blockstore/src/sgns-blockstore-build -C Debug --output-on-failure -L Tier1 --no-tests=error
  ```
- **Build after source edits:** drive the ExternalProject from the superbuild (re-stamps + rebuilds + re-installs):
  ```
  cmake --build thirdparty/build/Windows/Debug --config Debug --target sgns-blockstore
  ```
- **Tier contract:** `-L Tier1` fails closed (unlabeled tests never run); `--no-tests=error` fails empty selections; `tier1_static_audit` ctest fails the lane if a registration in `test/CMakeLists.txt` carries no `LABELS` line (D-14) — **the new consumer test MUST register with `set_tests_properties(... LABELS "Tier1")`** [VERIFIED: testing-tiers.md:64-80; test/CMakeLists.txt:216-226].
- Superbuild entry currently forces `-DTESTING:BOOL=ON` as the LAST cache arg so tests survive `_CMAKE_COMMON_CACHE_ARGS`'s `BUILD_TESTING=OFF` [VERIFIED: CommonTargets.cmake:895-919] — any edit to this entry must preserve that ordering.

## Q10 — header_hygiene_check.cmake: how the SDK-type guard works

[VERIFIED: thirdparty/sgns-blockstore/test/header_hygiene_check.cmake:1-50, read in full this session] A CMake script-mode (`-P`) ctest (`add_test(NAME header_hygiene ...)` at test/CMakeLists.txt:216-218, LABELS "Tier1"):
- `file(GLOB_RECURSE _headers "${SRC_DIR}/include/sgns-blockstore/*.hpp")` — scans **installed-header candidates only** (src/ headers invisible to it).
- Bans `#include` lines matching: `"ipfs_lite/ipfs/"`, `"SuperGenius/"`, `"GeniusSDK/"`, `"GeniusWallet/"`, `"minio"` — FATAL_ERROR on first hit.
- New declarations stay within it trivially: the 3-arg `CidOf` needs no new include (`HashType` is already visible in Cid.hpp via `content_identifier.hpp` → `multihash.hpp` → `hash_type.hpp` [VERIFIED: content_identifier.hpp:9-14 includes multihash.hpp]); `OpenMinioS3Client` needs only types already declared in `S3Client.hpp`. A blake2 include would appear ONLY in `src/Cid.cpp` — unscanned. If the planner wants belt-and-braces, the banned list can gain `"blake2"` — but the letter of the check is SDK-type containment and stays the planner's call.

---

## Recommended implementation approach (2-wave split)

### Wave 1 — 06-01-PLAN.md (LIB-01)
1. **Build wiring first** (it gates everything): sgns-blockstore `CMakeLists.txt` gains `find_package(ipfs-lite-cpp CONFIG REQUIRED)`; `src/CMakeLists.txt` links `PRIVATE ipfs-lite-cpp::blake2`; `thirdparty/build/CommonTargets.cmake` sgns-blockstore entry gains `-Dipfs-lite-cpp_DIR:PATH=${_FINDPACKAGE_IPFS_LITE_CONFIG_DIR}` and `DEPENDS ... ipfs-lite-cpp` (keep `-DTESTING:BOOL=ON` last). Rebuild superbuild target; confirm Tier-1 still green (no source changes yet — pure additive link).
2. **`Cid.hpp`/`Cid.cpp`:** declare + implement the 3-arg overload `CidOf(bytes, codec, HashType)` (sha-256 branch = existing composition; blake2b-256 branch = `sgns::crypto::blake2b::blake2b_256` → `Multihash::create(blake2b_256, ...)` → 3-arg `Cid` ctor, mirroring `getCidOf` exactly); unsupported `HashType` → throw `std::invalid_argument` (D-03/D-04). Update Cid.hpp's `@note` (it currently documents the sha-256-only D-08 posture — the note text must describe the widened pair). 2-arg form literally untouched.
3. **Gate widening:** at the three sites (or one consolidated internal helper — planner's call): accept `sha256` OR `blake2b_256`, throw otherwise; message updated once (not per-backend if consolidated).
4. **Verify branching:** the six sites (Q5 table) switch to the 3-arg overload with `cid.content_address.getType()`.
5. **`CodecToken`:** add `DAG_CBOR → "dag-cbor"`.
6. **Vectors:** derive + pin (Q4 procedure; two-source discipline), produce + commit the D-02 cross-check artifact, then extend the conformance kit: blake2b/DAG_CBOR roundtrip suite (all three backends via the macro), byte-flip-Corrupt-with-attribution case, `dag-cbor` key-layout observable (S3 fake), re-targeted rejection suite (sha-512 exemplar) in the kit + per-backend tests, `PutMany` mixed-batch retarget.
7. **Verify blocks:** superbuild build + Tier-1 ctest (Q9 commands) + `header_hygiene` green.

### Wave 2 — 06-02-PLAN.md (LIB-02; blocked on Wave 1)
1. **Factory:** declare `OpenMinioS3Client(const S3ClientConfig&) -> result<std::shared_ptr<S3Client>, BlockStatus>` in installed `S3Client.hpp` (Doxygen per Coding Standards; document the D-06 eager-validation/zero-I/O contract + the BaseUrl-snapshot note); define in `src/MinioS3Client.cpp` wrapping `MinioS3Client::Open`.
2. **Consumer proof (before hardening — D-07):** standalone CMake project under `test/` (e.g. `test/out_of_tree_consumer/`): own `CMakeLists.txt` with `find_package(sgns-blockstore CONFIG REQUIRED)` pointed via `-Dsgns-blockstore_DIR` at the install tree (plus the sibling `*_DIR` hints: `libp2p_DIR`, `RocksDB_DIR`, `miniocpp_DIR`, `httplib_DIR`, `nlohmann_json_DIR`, `pugixml_DIR`, and post-Wave-1 `ipfs-lite-cpp_DIR`); one TU that constructs `S3ClientConfig{...}` and calls `OpenMinioS3Client(...)` — compile+link+construct only, zero network; `EXPECT_TRUE(opened.has_value())`-style minimal runtime check (a config-valid construct against a non-listening endpoint must still SUCCEED at construction — that IS the D-06 no-I/O proof).
3. **Registration as Tier-1 hermetic ctest:** the sub-project builds+runs via an outer `add_test` (script driving `cmake -S/-B` + build + exe) OR configure-at-build-time — mechanics are planner discretion; MUST carry `LABELS "Tier1"` (D-14 audit) and run with no network. First run RED against the current config.cmake.in; record the forced failure; then harden config.cmake.in (`find_dependency(libp2p CONFIG)`, `find_dependency(miniocpp CONFIG)`, `find_dependency(ipfs-lite-cpp CONFIG)` — ordered before the targets include) until green. Stop there (D-07: nothing the minimal consumer doesn't force).
4. **Verify blocks:** rebuild + full Tier-1 lane + explicit re-run of the complete v1.0 sha-256 suite unchanged (SC3).

## Risks / landmines

1. **Duplicate-symbol collision if blake2 is vendored instead of linked (CRITICAL).** ipfs-lite's `blake2b.o` exports unrenamed `blake2b_init/update/final` (Q1). A second vendored copy in sgns-blockstore links fine standalone but collides when Phase 7's SuperGenius links both archives. Never vendor; link `ipfs-lite-cpp::blake2`.
2. **Ordering landmine in CommonTargets.cmake:** `-DTESTING:BOOL=ON` must remain the LAST cache arg of the sgns-blockstore entry; inserting `-Dipfs-lite-cpp_DIR` after it re-breaks the test gate (CommonTargets.cmake:895-918 comments).
3. **`toString` for DAG_CBOR CIDs is asserted, not proven.** `DeriveKey`'s "practically unreachable" comment was written for sha-256 CIDv1/v0. The Wave-1 conformance run must exercise `ContentIdentifierCodec::toString` on DAG_CBOR+blake2b-256 CIDs explicitly (the key-layout observable does this for free) — if it failed, DeriveKey's Corrupt mapping fires and the roundtrip test catches it loudly.
4. **Transcription errors in pinned literals.** Precedent: cid_spike_test.cpp:66-72 records a research-doc constant that had a wrong character at position 33. D-02's two-source bar + committed cross-check log is the mitigation; never pin a literal from one source or from memory.
5. **The miniocpp consumer-config re-run in the standalone consumer.** `miniocpp-deps.cmake` has a git-clone-source fallback for httplib — under D-07/D-08 hermeticity, the consumer must resolve httplib/nlohmann_json/pugixml via config dirs (no network clone ever runs in CI). Point `*_DIR`s explicitly; if the QUIET-find httplib trap (sgns-blockstore/CMakeLists.txt:35-44) bites the consumer too, the fix belongs in the consumer's CMakeLists (pass `httplib_DIR`), not in config.cmake.in.
6. **`MakeBlake2bCid()`'s fake digest vs. real vectors.** After widening, a Put of the fake-digest CID with any bytes fails Corrupt (not gate-throw) — the helper remains useful only for Has/GetSize/PutMany gate probes and must not be reused as a "roundtrip" CID.
7. **Superbuild rebuild latency / stale stamps.** Editing only `CommonTargets.cmake` requires re-running the superbuild configure (`cmake ...` in `thirdparty/build/Windows/Debug`) for the new `-D` args to reach the ExternalProject; a plain `--build` after touching only the entry may skip reconfiguration silently. Verify the sub-build `CMakeCache.txt` contains `ipfs-lite-cpp_DIR` after rebuild.
8. **Release tree is stale.** `thirdparty/build/Windows/Release/` predates sgns-blockstore (no minio-cpp/pugixml/json entries). All Phase-6 verify commands target the Debug tree (Q9); plans must not assume Release exists.

## Planner inputs (exact signatures, enums, paths, commands)

**Signatures to add:**
```cpp
// include/sgns-blockstore/Cid.hpp (overload; 2-arg form untouched)
outcome::result<Cid> CidOf(gsl::span<const uint8_t> bytes,
                           libp2p::multi::MulticodecType::Code codec,
                           libp2p::multi::HashType hash);   // throws std::invalid_argument for hash outside {sha256, blake2b_256}

// include/sgns-blockstore/S3Client.hpp (free function, namespace sgns::blockstore)
result<std::shared_ptr<S3Client>, BlockStatus> OpenMinioS3Client(
    const S3ClientConfig& config);
```

**Enums/constants (verbatim from tree):**
- `HashType`: `sha256 = 0x12`, `sha512 = 0x13`, `blake2b_256 = 0xb220` (libp2p multi/hash_type.hpp:17-22)
- `MulticodecType::Code`: `RAW = 0x55`, `DAG_PB = 0x70`, `DAG_CBOR = 0x71` (libp2p multi/multicodec_type.hpp:32-34)
- `Multihash::kMaxHashLength = 127` (libp2p multi/multihash.hpp:35)
- `StatusClass { NotFound, TemporarilyUnavailable, Corrupt, Unauthorized }`; `BlockSource { Memory, Local, Remote, Peer, Caller, Unknown }` (BlockStatus.hpp:24-51)
- blake2b call: `sgns::crypto::blake2b::blake2b_256(gsl::span<const uint8_t>) -> Blake2b256Hash` (Blob<32>), header `crypto/blake2/blake2b160.hpp`, target `ipfs-lite-cpp::blake2`

**Ground truth:** `sgns::common::getCidOf` — `thirdparty/ipfs-lite-cpp/primitives/cid/cid.cpp:129-136` (V1 + DAG_CBOR + blake2b_256).

**Widening sites (file:line):** gates Memory:23 / Local:35 / S3:27 (+ PutMany pre-passes Memory:157, Local:532, S3:244); verify Memory:71,108 / Local:305,427 / S3:124,177; `CodecToken` S3:43-53.

**Paths:**
- Install tree: `thirdparty/build/Windows/Debug/sgns-blockstore/` (config at `lib/cmake/sgns-blockstore`)
- Sibling package configs (for consumer `*_DIR` hints): `.../Debug/libp2p/lib/cmake/libp2p`, `.../Debug/rocksdb/lib/cmake/rocksdb`, `.../Debug/minio-cpp/lib/cmake/miniocpp` (+ `.../minio-cpp/lib/cmake/httplib`), `.../Debug/json/share/cmake/nlohmann_json` [VERIFIED: CommonTargets.cmake:807], `.../Debug/pugixml/lib/cmake/pugixml`, `.../Debug/ipfs-lite-cpp/lib/cmake/ipfs-lite-cpp`
- Evidence dir precedent: `thirdparty/sgns-blockstore/docs/evidence/`

**Commands (Windows workstation):**
```
cmake --build thirdparty/build/Windows/Debug --config Debug --target sgns-blockstore
ctest --test-dir thirdparty/build/Windows/Debug/sgns-blockstore/src/sgns-blockstore-build -C Debug --output-on-failure -L Tier1 --no-tests=error
```

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|---|---|---|---|---|
| Superbuild Debug tree (VS) | build + install + tests | ✓ | `thirdparty/build/Windows/Debug` | — |
| Python (blake2b independent derivation) | D-02 vector pinning | ✓ | 3.13.4 | RFC/KAT cross-read only (weaker) |
| ipfs-lite-cpp install tree (blake2 + getCidOf) | Wave-1 link + D-02 cross-check | ✓ | `.../Debug/ipfs-lite-cpp` | — |
| Network / live endpoints | nothing (Tier-1 hermetic) | — | — | explicitly not needed |

## Assumptions Log

| # | Claim | Section | Risk if wrong |
|---|---|---|---|
| A1 | `blake2b-256("") = 0e5751c0...fe3a8` (training-memory literal) | Q4 | Wrong pinned vector; MUST re-derive via Python before pinning (two-source bar makes this self-catching) |
| A2 | `varint(0xb220) = a0 e4 02` (session arithmetic) | Q4 | Wrong CID-string derivation in the dev script; cross-check run catches it |
| A3 | DAG_CBOR CIDv1 strings start `bafyre...` | Q4/Q6 | Cosmetic (test prefixes); toString round-trip in kit proves the real value |
| A4 | `ContentIdentifierCodec::toString` handles DAG_CBOR CIDv1 | Q6 | DeriveKey returns Corrupt; key-layout conformance test catches loudly (landmine 3) |
| A5 | minio `Client` construction performs no network I/O (lazy connect) | Q7/D-06 | If false, factory construction would touch network; the SC4 consumer's construct-against-dead-endpoint check exposes it immediately |
| A6 | `header_hygiene` stays green with no new includes in installed headers | Q7/Q10 | None realistically — both additions need only already-visible types (verified includes) |

## Open Questions (all RESOLVED — dispositions cite the post-split plan locations)

1. **Consolidation of the three gates** — discretion, planner's call; evidence says trivial (identical bodies). Recommend consolidating (one message to update, one place the accepted set lives).
   **(RESOLVED)** No consolidation — one gate copy per backend, per the v1.0 convention (06-02-PLAN.md, Task 1, step 1).
2. **`OpenMinioS3Client` error style for bad config** — evidence (S3BlockStore::Open, MinioS3Client::Open) says throw `invalid_argument` for programmer error; D-05/D-06 letters don't force `result`-slot config errors. Recommend keep-throw, document in Doxygen.
   **(RESOLVED)** Keep-throw + Doxygen-documented contract (06-03-PLAN.md, Task 1).
3. **Consumer-project mechanics under `test/`** — standalone CMake project driven by an outer `add_test` (cmake -S/-B + build + run in one script) is the shape D-08 names; exact glue is planner discretion. The `sgns-blockstore-smoke` dir in the Debug tree [VERIFIED: listing] shows a prior ad-hoc out-of-tree build existed — inspect it for prior art before choosing.
   **(RESOLVED)** Script-mode ctest driver + standalone project under test/out_of_tree_consumer (06-03-PLAN.md, Task 2).
4. **Journal-tooling gates** (`MarkUploadedDurable`/`GetUploadState` on blake2b CIDs, local_block_store_test.cpp:490-492) — they ride the store gate, so they widen automatically; confirm the re-targeted tests assert sha-512 throws there too.
   **(RESOLVED)** sha-512 retarget + blake2b journal-tooling acceptance asserted (06-02-PLAN.md, Task 1, step 5); blake2b spike pins at 06-01-PLAN.md, Task 2.

## Sources

### Primary (HIGH confidence — read from the tree this session)
- `thirdparty/sgns-blockstore/` — src/{Cid,MemoryBlockStore,LocalBlockStore,S3BlockStore,MinioS3Client}.cpp/.hpp, include/sgns-blockstore/{Cid,S3Client,S3BlockStore,BlockStatus}.hpp, test/{conformance/BlockStoreConformanceTests.hpp, memory_block_store_test.cpp, local_block_store_test.cpp, s3_block_store_test.cpp, cid_spike_test.cpp, api_hygiene_test.cpp, CMakeLists.txt, header_hygiene_check.cmake}, CMakeLists.txt, cmake/config.cmake.in, docs/testing-tiers.md, docs/evidence/
- `thirdparty/ipfs-lite-cpp/` — crypto/blake2/{blake2b.h,blake2b160.hpp,blake2b160.cpp,CMakeLists.txt}, primitives/cid/{cid.hpp,cid.cpp}, CMakeLists.txt
- `thirdparty/libp2p/include/libp2p/multi/{hash_type,multicodec_type,multihash,content_identifier}.hpp`, `crypto/hasher.hpp`, `crypto/sha/sha256.hpp`
- `thirdparty/build/CommonTargets.cmake` (ipfs-lite-cpp:498-533, minio-cpp/pugixml/json:780-860, sgns-blockstore:862-920)
- Install-tree artifacts: `sgns-blockstoreTargets.cmake`, `ipfs-lite-cppConfig.cmake`, `miniocpp-config.cmake` + `miniocpp-deps.cmake` (all read from `thirdparty/build/Windows/Debug/`)
- `.planning/workstreams/rocksdb-backup/` — REQUIREMENTS.md, STATE.md, ROADMAP.md (Phase 6), 06-CONTEXT.md, milestones/v1.0-phases/{01,03,04}-CONTEXT.md

### Secondary (MEDIUM confidence — cited, not fetched this session)
- RFC 7693 (BLAKE2) — https://www.rfc-editor.org/rfc/rfc7693
- RFC 8949 (CBOR) — https://www.rfc-editor.org/rfc/rfc8949
- BLAKE2 official KAT — https://github.com/BLAKE2/BLAKE2/tree/master/testvectors
- multibase/multicodec tables — https://github.com/multiformats/multibase , https://github.com/multiformats/multicodec

## Metadata

**Confidence breakdown:**
- Standard stack (blake2b entry point, CMake targets): HIGH — every claim read from the pinned tree/install artifacts this session
- Architecture (widening mechanics, wave split): HIGH — all six verify sites + three gates + export surface read and quoted
- Pitfalls: HIGH for code-level landmines (read); MEDIUM for pinned-literal discipline (mitigated by D-02 two-source bar)

**Research date:** 2026-10-22
**Valid until:** tree-stable (submodule pins unchanged) — no external fast-moving dependency
