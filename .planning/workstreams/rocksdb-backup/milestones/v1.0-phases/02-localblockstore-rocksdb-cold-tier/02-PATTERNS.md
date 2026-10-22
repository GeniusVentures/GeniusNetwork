# Phase 2: LocalBlockStore (RocksDB Cold Tier) - Pattern Map

**Mapped:** 2026-10-20
**Files analyzed:** 11 (4 new, 7 modified)
**Analogs found:** 11 / 11 (9 exact/precedent, 2 role-match)

**Tracked-source gate (#3645):** every analog below verified `git ls-files` non-empty in its owning repo (`thirdparty/sgns-blockstore`, `thirdparty` superbuild, `thirdparty/ipfs-lite-cpp`, `SuperGenius` — all separate submodules). No gitignored mirror paths used.

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `thirdparty/sgns-blockstore/include/sgns-blockstore/LocalBlockStore.hpp` (NEW) | model (public backend header, pimpl) | CRUD | `include/sgns-blockstore/MemoryBlockStore.hpp` + `Cid.hpp` (result alias) + `Options.hpp` (options-struct convention) | exact |
| `thirdparty/sgns-blockstore/src/LocalBlockStore.cpp` (NEW) | service (backend impl) | file-I/O + batch (one WriteBatch per mutation) | `src/MemoryBlockStore.cpp` (gates/status/verification) + `SuperGenius/src/storage/rocksdb/rocksdb.cpp` (open/deleter/sync) + `SuperGenius/src/storage/database_error.cpp` (Status switch) + `thirdparty/ipfs-lite-cpp/ipfs_lite/ipfs/impl/datastore_rocksdb.cpp` (cid.toBytes() key) | exact (role); substrate precedents are cross-repo |
| `thirdparty/sgns-blockstore/include/sgns-blockstore/BlockStoreTooling.hpp` (MOD) | interface (audit enumeration) | batch scan | itself (`ForEach` pure-virtual shape, lines 44-59) | exact (self-extension) |
| `thirdparty/sgns-blockstore/CMakeLists.txt` (MOD) | config | — | itself: `find_package(libp2p CONFIG REQUIRED)` line 18 | exact (self-extension) |
| `thirdparty/sgns-blockstore/src/CMakeLists.txt` (MOD) | config | — | itself: `add_library` + `target_link_libraries` block, lines 1-12 | exact (self-extension) |
| `thirdparty/sgns-blockstore/test/CMakeLists.txt` (MOD) | config | — | itself: `addtest()` entries + conformance include-dir line 18 | exact (self-extension) |
| `thirdparty/sgns-blockstore/test/local_block_store_test.cpp` (NEW) | test | CRUD conformance + behavior | `test/memory_block_store_test.cpp` | exact |
| `thirdparty/sgns-blockstore/test/local_block_store_crash_test.cpp` (NEW) | test | file-I/O (crash/close/reopen) | `test/memory_block_store_test.cpp` (fixture/helpers ONLY — no crash mechanics precedent) | role-match |
| `thirdparty/sgns-blockstore/test/api_hygiene_test.cpp` (MOD) | test (compile-time guards) | — | itself: include-everything block lines 35-44 + static_asserts lines 145-175 | exact (self-extension) |
| `thirdparty/build/CommonTargets.cmake` (MOD) | config (superbuild orchestration) | — | ipfs-lite-cpp entry lines 512-514 (`Snappy_DIR`+`RocksDB_DIR` adjacent) + rocksdb entry lines 141-175 | exact precedent |
| `thirdparty/sgns-blockstore/cmake/config.cmake.in` (MOD, optional per RESEARCH Pitfall 5) | config | — | `thirdparty/boost/libs/nowide/Config.cmake.in` (`find_dependency` precedent) + itself | role-match |

**Note on D-06/D-05 surfaces:** the `UploadState` enum, `MarkUploadedAccepted`/`MarkUploadedDurable` transitions, state accessor, `EvictLocal`, and the crash-point seam all live on `LocalBlockStore` (concrete type) — the concrete-method placement pattern is `MemoryBlockStore::EvictLocal` (`MemoryBlockStore.hpp` ~66-73). `GetPendingUploads` lands on `BlockStoreTooling` as pure virtual (matches `ForEach`'s shape; only LocalBlockStore implements it in v1 — RESEARCH Open Question 1 recommendation).

## Pattern Assignments

### `include/sgns-blockstore/LocalBlockStore.hpp` (NEW — model header, CRUD)

**Analog:** `include/sgns-blockstore/MemoryBlockStore.hpp` (96 lines — copy the whole shape)

**Include block pattern** (lines 13-17 — std-first, blank line, project headers, no rocksdb anywhere):
```cpp
#include <map>
#include <vector>

#include <sgns-blockstore/Block.hpp>
#include <sgns-blockstore/BlockStore.hpp>
#include <sgns-blockstore/FaultController.hpp>
```
For LocalBlockStore add `BlockStoreTooling.hpp` (third base) and `<memory>`/`<string>` (pimpl + options). **Pimpl rule (RESEARCH Pattern 1): zero `rocksdb/*` includes in this header** — all RocksDB types live behind `class Impl;` forward-declared here, defined in the `.cpp`.

**Dual/triple inheritance + out-of-line destructor** (lines 44-49):
```cpp
    class MemoryBlockStore : public BlockStore, public FaultController
    {
    public:
        ~MemoryBlockStore() override = default;
```
LocalBlockStore: `class LocalBlockStore final : public BlockStore, public FaultController, public BlockStoreTooling` with `~LocalBlockStore() override;` **declared only** (defined in .cpp — required for `std::unique_ptr<Impl>` with incomplete type).

**Override declaration pattern** (lines 52-64 — `@copydoc` Doxygen on every override):
```cpp
        /** @copydoc BlockStore::Put() */
        result<PutOutcome, BlockStatus> Put(
            const Cid& cid, gsl::span<const uint8_t> bytes,
            const WriteOptions& options = {}) override;
```

**Concrete backend-only method pattern** (lines 66-73, EvictLocal — this is exactly how `MarkUploadedAccepted`/`MarkUploadedDurable`/`GetUploadState`/`EvictLocal`/crash-seam setters get declared, with a decision-citing docstring):
```cpp
        /**
         * @brief Remove this store's LOCAL copy of a block (D-16).
         *
         * Concrete method on the backend type ONLY - never on BlockStore.
         * Idempotent: success whenever no local bytes remain...
         */
        result<void, BlockStatus> EvictLocal(const Cid& cid);
```

**Private member pattern** (lines 91-93 — trailing-underscore members, one is the seam state):
```cpp
    private:
        std::map<Cid, std::vector<uint8_t>> storage_; ///< operator<-keyed (no std::hash on ContentIdentifier...)
        FaultKind fault_ = FaultKind::None; ///< conformance seam state (never read by production paths)
```

**Options-struct convention:** copy `Options.hpp` (whole file, 44 lines) shape for `LocalBlockStoreOptions` — plain struct, Doxygen on every field, defaults inline (`bool verify = true;` style). RESEARCH recommends defaults `avoid_flush_during_shutdown = true` documented in-field.

**Header hygiene:** include guard `SGNS_BLOCKSTORE_LOCALBLOCKSTORE_HPP`, `@file/@brief` header comment, namespace `sgns::blockstore`, Ullman braces (Coding Standards.md).

---

### `src/LocalBlockStore.cpp` (NEW — service impl, file-I/O + batch)

**Primary analog:** `src/MemoryBlockStore.cpp` (gate order, status mapping, verification — the discipline carries over verbatim; only the storage substrate changes)

**Entry-gate order — copy exactly** (anonymous-namespace helpers lines 19-56, then every op):
```cpp
        void ValidateCidHash(const Cid& cid)
        {
            if (cid.content_address.getType() != libp2p::multi::HashType::sha256)
            {
                throw std::invalid_argument(
                    "sgns::blockstore: CID multihash type is not sha-256 - ...");
            }
        }

        std::optional<BlockStatus> FaultGate(FaultKind fault)
        {
            switch (fault)
            {
                case FaultKind::Unavailable:
                    return BlockStatus{StatusClass::TemporarilyUnavailable,
                                       BlockSource::Memory,
                                       "fault injection: backend unavailable"};
                ...
```
LocalBlockStore: `BlockSource::Memory` becomes `BlockSource::Local` (the frozen enum's local-persistent member, `BlockStatus.hpp` lines 38-47). Gate order per op: `ValidateCidHash` → `FaultGate` → real op.

**Put core: verify-at-facade + alreadyPresent** (lines 59-93):
```cpp
        ValidateCidHash(cid);
        if (auto gate = FaultGate(fault_)) { return gate.value(); }
        // NOTE: CidOf carries the default error type (std::error_code), so
        // its failure is mapped explicitly - never OUTCOME_TRY'd across the
        // BlockStatus-typed envelope (mismatched error types).
        auto computed = CidOf(bytes, cid.content_type);
        if (!computed) { return BlockStatus{StatusClass::Corrupt, BlockSource::Caller, ...}; }
        if (!(computed.value() == cid)) { return BlockStatus{StatusClass::Corrupt, BlockSource::Caller,
                               "Put rejected: bytes do not hash to the claimed CID"}; }
        const bool already_present = storage_.find(cid) != storage_.end();
        ...
        return PutOutcome{DurabilityLevel::LocalCommitted, already_present};
```
LocalBlockStore replaces the map write with the one-WriteBatch commit (blocks CF + journal CF, journal `PendingUpload` **only when `!already_present`** — RESEARCH Pitfall 6), and computes `already_present` via `db_->Get(ro_, blocks_, key, &existing)` read-before-write.

**Get corruption seam — the copy mechanic** (lines 111-115):
```cpp
        auto bytes = it->second; // deliberate copy - corruption is induced on the copy
        if (fault_ == FaultKind::CorruptData && !bytes.empty())
        {
            bytes[0] = static_cast<uint8_t>(~bytes[0]); // documented seam mechanic
        }
```
This is the fault-induced path — **NO eviction** (kit asserts non-sticky). The D-09 self-heal path is a *separate* branch: stored bytes fail `CidOf` with `fault_ != CorruptData` → return `Corrupt`+`Local` for THIS call AND commit removal WriteBatch{block, journal}.

**PutMany pattern** (lines 155-181): pre-validate whole batch (throw before any write), outer fault gate once, then per-element `Put` preserving index correspondence — copy verbatim.

**EvictLocal pattern** (lines 162-167):
```cpp
    result<void, BlockStatus> MemoryBlockStore::EvictLocal(const Cid& cid)
    {
        storage_.erase(cid);
        return outcome::success(); // idempotent post-state: no local bytes remain
    }
```
LocalBlockStore: one WriteBatch{Delete(blocks, key), Delete(journal, key)}, sync write — unconditional (D-10), idempotent success.

**SetFault/GetFault** (last two methods): trivial member get/set — copy verbatim.

**Secondary analogs (substrate mechanics — cross-repo precedents):**

*RocksDB open + deleter + sync* — `SuperGenius/src/storage/rocksdb/rocksdb.cpp` lines 56-70:
```cpp
        auto status = DB::Open( l->options_, l->path_, &db );
        if ( status.ok() )
        {
            // Wrap DB* into a shared_ptr with a custom deleter to ensure cleanup
            l->db_ = std::shared_ptr<DB>( db,
                                          []( DB *ptr )
                                          {
                                              if ( ptr )
                                              {
                                                  ptr->Close(); // Properly release RocksDB handles
                                                  delete ptr;
                                              }
                                          } );
            l->wo_.sync = true;
```
Also copy `info_log_level = ERROR_LEVEL` (line 42 of same file). LocalBlockStore uses CF-vector `DB::Open` (RESEARCH Code Examples) and teardown `DestroyColumnFamilyHandle(blocks)` → `DestroyColumnFamilyHandle(journal)` → `Close()` → `delete db_` — NEVER destroy the default CF handle.

*Status→taxonomy switch* — `SuperGenius/src/storage/database_error.cpp` lines 51-96:
```cpp
    DatabaseError error_from_rocksdb( rocksdb::Status::Code code )
    {
        using E = sgns::storage::DatabaseError;
        switch ( code )
        {
            case rocksdb::Status::kOk:
                return E::OK;
            case rocksdb::Status::kNotFound:
                return E::NOT_FOUND;
            case rocksdb::Status::kCorruption:
                return E::CORRUPTION;
            ...
```
Switch on named `Status::Code` constants only (never string-match `ToString()`, never enumerate) — one `MapStatus(const rocksdb::Status&, context)` helper mapping to `BlockStatus{NotFound|Corrupt|TemporarilyUnavailable, BlockSource::Local, ...}` per RESEARCH.

*CID key encoding — the D-01 migration anchor* — `thirdparty/ipfs-lite-cpp/ipfs_lite/ipfs/impl/datastore_rocksdb.cpp` lines 12-20 + 44-49:
```cpp
        inline IPFS::outcome::result<common::Buffer> encode( const CID &value )
        {
            BOOST_OUTCOME_TRY( auto encoded, value.toBytes() );
            return common::Buffer( std::move( encoded ) );
        }
        ...
        IPFS::outcome::result<void> RocksdbDatastore::set( const CID &key, Value value )
        {
            BOOST_OUTCOME_TRY( auto encoded_key, encode( key ) );
            return rocksdb_->put( encoded_key, common::Buffer( std::move( value ) ) );
        }
```
Proof that `RocksdbDatastore` keys are exactly `cid.toBytes()` — LocalBlockStore's blocks-CF keys must be byte-identical (`ContentIdentifierCodec::encode(cid)`, the same bytes; map its failure explicitly, no `BOOST_OUTCOME_TRY` — different outcome namespace).

---

### `include/sgns-blockstore/BlockStoreTooling.hpp` (MOD — D-05 lands here)

**Analog:** itself, `ForEach` pure virtual (lines 44-59):
```cpp
        virtual result<void, BlockStatus> ForEach(
            const std::function<void(const Cid&, gsl::span<const uint8_t>)>& visitor)
            = 0;
```
Add `GetPendingUploads()` as pure virtual (`= 0`, RESEARCH Open-Question-1 recommendation — matches ForEach's shape; only LocalBlockStore implements it in v1), returning `result<std::vector<Cid>, BlockStatus>` (add `<vector>` include). Extend the class docstring's ordering-contract note (lines 33-41) to cover the pending set (same lexicographic-over-encoded-CID-bytes order — RocksDB CF iterator with default BytewiseComparator satisfies it naturally). **Do not touch any frozen header other than this additive method.**

---

### `test/local_block_store_test.cpp` (NEW — conformance + behavior suite)

**Analog:** `test/memory_block_store_test.cpp` (~389 lines — copy structure wholesale)

**Helper + fixture pattern** (lines 38-58 — the no-default-ctor landmine handled by member-initializers):
```cpp
    Cid MakeCid(const std::string& payload)
    {
        return CidOf(SpanOf(payload), MulticodecType::Code::RAW).value();
    }

    // NOTE: ContentIdentifier has no default constructor, so the CID
    // members carry member-initializers (fixture must stay default-
    // constructible for TEST_F).
    class MemoryBlockStoreTest : public ::testing::Test
    {
    public:
        std::shared_ptr<MemoryBlockStore> store_{std::make_shared<MemoryBlockStore>()};
        std::string payload_a_ = "block a payload";
        std::string payload_b_ = "block b payload - different length";
        Cid cid_a_ = MakeCid(payload_a_);
        Cid cid_b_ = MakeCid(payload_b_);
    };
```
LocalBlockStore fixture: `Open()` can fail — factory helper checks the result with `ADD_FAILURE() + nullptr` (never `.value()` on a possibly-failed `policy::terminate` envelope), and creates a **fresh unique directory per invocation** (monotonic counter, short relative path under the build tree — RESEARCH Pitfall 4).

**Kit instantiation pattern** (last lines of file, ~381-389 — factory invoked per case):
```cpp
SGNS_BLOCKSTORE_CONFORMANCE_TESTS(
    MemoryBlockStoreConformance,
    [] { return std::shared_ptr<sgns::blockstore::BlockStore>(
        std::make_shared<sgns::blockstore::MemoryBlockStore>()); })
```
LocalBlockStore: same macro, factory lambda opening a fresh dir and returning `std::shared_ptr<BlockStore>` (upcast from the concrete Open result).

**Behavior-test doc pattern:** every TEST carries `@given/@when/@then` comment blocks; assertions are plain `ASSERT_TRUE(res)` + `res.value()`/`res.error()` (no outcome macros — D-11). Mirror the fault tests (Unavailable/CorruptData/Unauthorized, lines ~213-280) — they come free from the kit; add backend-specific behavior only (journal transitions, EvictLocal-on-RocksDB, re-Put no-regression per RESEARCH Pitfall 6).

---

### `test/local_block_store_crash_test.cpp` (NEW — crash/reopen, D-07/D-08)

**Analog (partial):** `test/memory_block_store_test.cpp` — copy the includes/helpers/fixture discipline (above) and `@given/@when/@then` style. **No in-repo crash/reopen test exists** — the WAL-replay assertion structure comes from RESEARCH.md's verified "Crash test skeleton" (crash-before-commit → NotFound + empty pending set; crash-after-commit → block + PendingUpload both present). Tests hold the concrete `std::shared_ptr<LocalBlockStore>` (fixture-controlled lifecycle); the corruption self-heal test opens a second raw `rocksdb::DB` handle on the same directory to rewrite a value (test target links `RocksDB::rocksdb` directly — allowed per RESEARCH).

---

### `test/api_hygiene_test.cpp` (MOD — include-everything grows)

**Analog:** itself. Extend the include block (lines 35-44) with `#include <sgns-blockstore/LocalBlockStore.hpp>` (eleventh public header — keeps the standalone-consumer proof complete) and extend the D-16 placement asserts (lines 165-168):
```cpp
static_assert(!HasEvictLocal<sgns::blockstore::BlockStore>::value,
              "D-16 violation: EvictLocal must not exist on BlockStore");
static_assert(HasEvictLocal<sgns::blockstore::MemoryBlockStore>::value,
              "D-16 violation: MemoryBlockStore must expose EvictLocal");
```
→ add `static_assert(HasEvictLocal<sgns::blockstore::LocalBlockStore>::value, ...)`. Pimpl keeps this TU free of rocksdb includes; the comment about "links exactly sgns-blockstore + p2p::p2p_cid" should be updated to mention the transitive RocksDB consumer dependency.

---

### `thirdparty/sgns-blockstore/CMakeLists.txt` (MOD — root)

**Analog:** itself, line 18:
```cmake
find_package(libp2p CONFIG REQUIRED)
```
Add directly beside it: `find_package(RocksDB CONFIG REQUIRED)` — **NO version argument** (SameMajorVersion landmine, RESEARCH Pitfall 5). Nothing else changes (TESTING gate lines 23-29 stay; the `include(GNUInstallDirs)`/install blocks stay).

---

### `thirdparty/sgns-blockstore/src/CMakeLists.txt` (MOD)

**Analog:** itself, whole file (12 lines):
```cmake
add_library(sgns-blockstore STATIC
    Cid.cpp
    ContractHeaders.cpp
    MemoryBlockStore.cpp
)

target_link_libraries(sgns-blockstore
    PUBLIC p2p::p2p_cid
)
```
Add `LocalBlockStore.cpp` to the sources and `RocksDB::rocksdb` to `target_link_libraries` (PUBLIC — the pimpl `.cpp` needs it at link time; the imported target carries shlwapi/rpcrt4 automatically).

---

### `thirdparty/sgns-blockstore/test/CMakeLists.txt` (MOD)

**Analog:** itself, lines 1-6 + 18:
```cmake
addtest(memory_block_store_test memory_block_store_test.cpp)
target_link_libraries(memory_block_store_test
    sgns-blockstore
    p2p::p2p_cid
)
...
target_include_directories(memory_block_store_test PRIVATE ${CMAKE_SOURCE_DIR}/test/conformance)
```
Add two `addtest()` entries (`local_block_store_test`, `local_block_store_crash_test`) each linking `sgns-blockstore p2p::p2p_cid` (+ `RocksDB::rocksdb` for the crash test's raw second handle), each with the `test/conformance` include dir (crash test only if it uses kit helpers). `addtest()` comes from `cmake/functions.cmake` (gtest_main + xunit wiring — already available).

---

### `thirdparty/build/CommonTargets.cmake` (MOD — sgns-blockstore entry)

**Analog 1 — the RocksDB_DIR/Snappy_DIR adjacency precedent**, ipfs-lite-cpp entry lines 512-514:
```cmake
    -DSnappy_DIR:PATH=${_FINDPACKAGE_SNAPPY_DIR}
    -DRocksDB_DIR:PATH=${_FINDPACKAGE_ROCKSDB_DIR}
    -DSnappy_DIR:PATH=${_FINDPACKAGE_SNAPPY_DIR}
```
(Ipfs-lite-cpp duplicates Snappy_DIR — a quirk, not a pattern; the sgns-blockstore entry needs exactly one of each, inserted alphabetically among its cache args.) The variables are already exported: `_FINDPACKAGE_ROCKSDB_DIR` set at line 172, `_FINDPACKAGE_SNAPPY_DIR` at line 138.

**Analog 2 — DEPENDS-with-rocksdb precedent**, ipfs-lite-cpp line 523:
```cmake
    DEPENDS Microsoft.GSL spdlog tsl_hat_trie libp2p protobuf ${PROTOBUF_TARGET} rocksdb Boost.DI
```
The sgns-blockstore entry (lines 779-813) currently has `DEPENDS libp2p` (line 811) → becomes `DEPENDS libp2p rocksdb` (rocksdb itself `DEPENDS snappy`, line 171 — transitively satisfied).

**Do NOT disturb** the TESTING-last-arg block (lines 803-810) — `-DTESTING:BOOL=ON` must stay the final cache arg or the superbuild's forced `-DBUILD_TESTING:BOOL=OFF` wins and tests silently vanish.

---

### `thirdparty/sgns-blockstore/cmake/config.cmake.in` (MOD — optional, RESEARCH Pitfall 5)

**Analog:** `thirdparty/boost/libs/nowide/Config.cmake.in` lines 5-14:
```cmake
include(CMakeFindDependencyMacro)
...
  find_dependency(${dep})
...
include("${CMAKE_CURRENT_LIST_DIR}/@PROJECT_NAME@Targets.cmake")
```
Current file is one line (`include( "${CMAKE_CURRENT_LIST_DIR}/sgns-blockstoreTargets.cmake" )`). Prepend `include(CMakeFindDependencyMacro)` + `find_dependency(RocksDB CONFIG)` (no version) so downstream `find_package(sgns-blockstore)` resolves the imported target.

## Shared Patterns

### Result envelope (MANDATORY on every new signature)
**Source:** `include/sgns-blockstore/Cid.hpp` lines 25-34
**Apply to:** LocalBlockStore.hpp, BlockStoreTooling.hpp, all new methods
```cpp
    namespace outcome = libp2p::outcome;

    template <class R, class S = std::error_code,
              class NoValuePolicy = libp2p::outcome::policy::terminate>
    using result = libp2p::outcome::basic_result<R, S, NoValuePolicy>;
```
Never bare `outcome::result<..., BlockStatus>` (struct error type + default policy fails to instantiate); `.value()` on failure **terminates** — every call site checks `has_value()`/`if (res)` first. Never `OUTCOME_TRY`/`BOOST_OUTCOME_TRY` a `CidOf`/`encode` failure (std::error_code) into a BlockStatus envelope — map explicitly.

### Entry-gate order (ValidateCidHash → FaultGate → op)
**Source:** `src/MemoryBlockStore.cpp` lines 19-56 + every op body
**Apply to:** every LocalBlockStore operation including EvictLocal and the journal transitions (throw for programmer error, fault failure before touching RocksDB, then the real op).

### BlockStatus construction
**Source:** `include/sgns-blockstore/BlockStatus.hpp` lines 55-63 (`{StatusClass, BlockSource, message}` — message never empty, never a secret); LocalBlockStore uses `BlockSource::Local` (never `Memory`), `BlockSource::Caller` only for Put-path verification failures.

### Factory for fallible construction
**Source:** AGENTS.md Function Design ("Factory methods return `outcome::result<std::shared_ptr<T>>`") + `RocksdbDatastore::create` (`datastore_rocksdb.cpp` lines 27-33)
**Apply to:** `static result<std::unique_ptr<LocalBlockStore>, BlockStatus> Open(const LocalBlockStoreOptions&)`; throw `std::invalid_argument` on programmer-error args (empty path), return mapped BlockStatus on environment failures.

### Test discipline
**Source:** `test/memory_block_store_test.cpp` header comment + `BlockStoreConformanceTests.hpp` lines 1-24
**Apply to:** both new test files — plain GTest EXPECT/ASSERT, `@given/@when/@then` doc comments, member-initializer fixtures (Cid has no default ctor), fresh-store-per-case factories, snake_case test filenames (repo-local convention: `memory_block_store_test.cpp`, `api_hygiene_test.cpp`, `cid_spike_test.cpp`).

### C++17 + style baseline
**Source:** `thirdparty/sgns-blockstore/CMakeLists.txt` line 10 (`set(CMAKE_CXX_STANDARD 17)`), Coding Standards.md
**Apply to:** all new code — no C++20 (`std::void_t`/SFINAE patterns, not `requires`), Ullman braces, PascalCase types/headers, trailing-underscore members, Doxygen `@file/@brief` on every file and `@param/@return` on public APIs.

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `test/local_block_store_crash_test.cpp` (WAL-replay mechanics only) | test | file-I/O crash/reopen | No close-without-flush/reopen test exists anywhere in the workspace repos; fixture/helper patterns come from `memory_block_store_test.cpp`, assertion structure from RESEARCH.md's verified "Crash test skeleton" |
| RocksDB WriteBatch/CF machinery inside `src/LocalBlockStore.cpp` | service | batch | No column-family or WriteBatch usage exists in sgns-blockstore or SuperGenius (SuperGenius/ipfs-lite use single-CF default opens); use RESEARCH.md Code Examples (verified against in-tree 9.4.0 headers) — CF-vector Open, one-batch commit, teardown order |

## Metadata

**Analog search scope:** `thirdparty/sgns-blockstore/**` (complete — 10 headers, 3 src, 5 test files, 3 CMakeLists, 2 cmake templates), `thirdparty/build/CommonTargets.cmake` (rocksdb/ipfs-lite-cpp/sgns-blockstore entries), `thirdparty/ipfs-lite-cpp/ipfs_lite/ipfs/impl/datastore_rocksdb.{hpp,cpp}`, `SuperGenius/src/storage/rocksdb/rocksdb.cpp`, `SuperGenius/src/storage/database_error.cpp`, `SuperGenius/src/crdt/globaldb/globaldb.cpp` (RocksdbDatastore wiring), `thirdparty/boost/libs/*/Config.cmake.in` (find_dependency precedent)
**Files scanned:** ~30 read; 19 verified git-tracked via `git ls-files`
**Pattern extraction date:** 2026-10-20
