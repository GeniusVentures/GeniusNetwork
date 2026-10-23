# Phase 7: SuperGenius Build Wiring & Config Gate - Pattern Map

**Mapped:** 2026-10-23
**Files analyzed:** 12 (10 modify, 2 create)
**Analogs found:** 11 / 12 (7 exact, 4 role-match, 1 partial)

> All analog paths below verified git-TRACKED via `git ls-files` in the owning repo/submodule (SuperGenius, GeniusSDK, GeniusWallet, thirdparty/sgns-blockstore nested submodule, root). No gitignored mirror paths.

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `SuperGenius/build/CommonBuildParameters.cmake` | config (build system) | request-response (configure-time find_package) | same file: AsyncIOManager block `:406-409` + RocksDB `:118-121`; cross-tree: `thirdparty/sgns-blockstore/test/out_of_tree_consumer/CMakeLists.txt:19-33` | exact |
| `GeniusSDK/cmake/CommonBuildParameters.cmake` | config (build system) | request-response (configure-time find_package) | same file: AsyncIOManager `:313-317` + option gate `:205-212` | exact |
| `SuperGenius/src/crdt/globaldb/globaldb.hpp` | model (options struct + factory signature) | transform | same file: `BackupOptions` `:28-34` + defaulted `New()` param `:54-63` | exact |
| `SuperGenius/src/crdt/globaldb/globaldb.cpp` | service (factory impl) | transform | same file: `GlobalDB::New` `:67-92`, member assignment `:86-88` | exact |
| `SuperGenius/src/account/GeniusNode.hpp` | model (config state members) | file-I/O (config load) | `crdt_backup_config_` member (research-pinned `:1624`); `LoadCrdtConfig` decl `:1383` | role-match |
| `SuperGenius/src/account/GeniusNode.cpp` | service (config loader) | file-I/O + startup event | same file: `LoadCrdtConfig` `:552-610` (self-extension), `LoadLogConfig` member loop `:637`, ctor throw `:358-376` | exact |
| `SuperGenius/test/src/crdt/cold_storage_config_gate_test.cpp` **(NEW)** | test (hermetic GTest) | file-I/O (parse matrix) + batch | `thirdparty/sgns-blockstore/test/s3_block_store_test.cpp:162-206`; `SuperGenius/test/src/crdt/globaldb_integration.cpp:1-60` | role-match |
| `SuperGenius/test/src/crdt/CMakeLists.txt` | test config (registration) | — | same file `:1-38`; `thirdparty/sgns-blockstore/test/CMakeLists.txt:10-17` (LABELS) | exact |
| `GeniusWallet/assets/crdt_config.json` | config (shipped asset) | file-I/O | same file (current flat keys); nested-object shape: `GeniusWallet/assets/log_config.json:1-5` | role-match |
| `GeniusWallet/lib/settings/settings_screen.dart` | component (Flutter UI) | request-response (load→edit→save roundtrip) | same file: Network whitelist `:130-137` | exact |
| `SuperGenius/.github/workflows/cmake.yml` | config (CI) | batch (test selection) | same file ctest step `:604`/`:674-676`; lane command: `thirdparty/sgns-blockstore/docs/testing-tiers.md:55` | partial (no `-L` lane exists in-repo) |
| `supergenius-sharded-ipld-cache-architecture.md` | docs | — | same file: "Example runtime configuration" `:500-539` | role-match |

## Pattern Assignments

### `SuperGenius/build/CommonBuildParameters.cmake` (config, configure-time)

**Analog:** same file — the gated consumption block lands immediately after the AsyncIOManager block (`:406-409`), OUTSIDE the libssh2 `PREFER_CONFIG` window (`:384-405`).

**Placement boundary — the PREFER_CONFIG window** (`:384-405`, verbatim; new finds go AFTER `:405`, never inside):
```cmake
# Prefer package config files while loading Libssh2's dependencies.
# Libssh2 config calls `find_dependency(ZLIB)` without `CONFIG`, which can
# otherwise resolve to CMake's FindZLIB module on Windows CI.
set(_SGNS_CMAKE_FIND_PACKAGE_PREFER_CONFIG_WAS_DEFINED FALSE)
if(DEFINED CMAKE_FIND_PACKAGE_PREFER_CONFIG)
    set(_SGNS_CMAKE_FIND_PACKAGE_PREFER_CONFIG_WAS_DEFINED TRUE)
    set(_SGNS_CMAKE_FIND_PACKAGE_PREFER_CONFIG_PREV "${CMAKE_FIND_PACKAGE_PREFER_CONFIG}")
endif()
set(CMAKE_FIND_PACKAGE_PREFER_CONFIG ON)
...
unset(_SGNS_CMAKE_FIND_PACKAGE_PREFER_CONFIG_PREV)
unset(_SGNS_CMAKE_FIND_PACKAGE_PREFER_CONFIG_WAS_DEFINED)
```

**Direct precedent — AsyncIOManager consumption block** (`:406-409`, verbatim; insert the new gated block after `:409`):
```cmake
# AsyncIOManager
set(AsyncIOManager_INCLUDE_DIR "${_THIRDPARTY_BUILD_DIR}/AsyncIOManager/include")
set(AsyncIOManager_DIR "${_THIRDPARTY_BUILD_DIR}/AsyncIOManager/lib/cmake/AsyncIOManager")
find_package(AsyncIOManager CONFIG REQUIRED)
```

**Canonical hint style — RocksDB** (`:118-121`, verbatim; note `Snappy_DIR` at `:116-117` must already be set — it is, and the RocksDB chain needs it forwarded):
```cmake
# rocksdb
set(RocksDB_DIR "${_THIRDPARTY_BUILD_DIR}/rocksdb/lib/cmake/rocksdb")
find_package(RocksDB CONFIG REQUIRED)
```

**In-file cache-gate precedent** (`:12-13`, verbatim — the file's only existing gate; `option()` precedent lives in the SDK file, see below):
```cmake
# --------------------------------------------------------
# Set config of GTest
set(BUILD_TESTING "ON" CACHE BOOL "Build tests")
```

**Cross-tree analog — consumer find shape** (`thirdparty/sgns-blockstore/test/out_of_tree_consumer/CMakeLists.txt:19-33`, verbatim excerpt; httplib MUST be found explicitly FIRST — Phase-3 spike finding quoted in its comment):
```cmake
find_package(httplib CONFIG REQUIRED)

find_package(sgns-blockstore CONFIG REQUIRED)

add_executable(consumer_proof consumer_main.cpp)
target_link_libraries(consumer_proof PRIVATE sgns-blockstore::sgns-blockstore)
```

**Hint closure reference** (`thirdparty/sgns-blockstore/test/out_of_tree_consumer/run_consumer_proof.cmake:47-81`): the proven hint set to mirror is `sgns-blockstore_DIR, libp2p_DIR, RocksDB_DIR, Snappy_DIR, miniocpp_DIR, httplib_DIR, nlohmann_json_DIR, pugixml_DIR, ipfs-lite-cpp_DIR` (+ `CMAKE_PREFIX_PATH`, `CMAKE_MSVC_RUNTIME_LIBRARY`, `GSL_INCLUDE_DIR`). nlohmann_json's layout is `json/share/cmake/nlohmann_json` (GNUInstallDirs datadir) — already proven in this same file at `:486-487`.

---

### `GeniusSDK/cmake/CommonBuildParameters.cmake` (config, configure-time)

**Analog:** same file — AsyncIOManager `:313-317`; the SDK block must land AFTER `:323` (gnus_upnp) and BEFORE `find_package(SuperGenius CONFIG REQUIRED)` at **`:462`** (hard ordering constraint — once SuperGenius exports reference `sgns-blockstore::sgns-blockstore`, the SDK configure fails unless the target already exists).

**Option-gate precedent — the exact shape for `SGNS_COLD_STORAGE`** (`:205-212`, verbatim):
```cmake
option(Boost_USE_STATIC_RUNTIME "Use static runtimes" ON)

option(SGNS_STACKTRACE_BACKTRACE "Use BOOST_STACKTRACE_USE_BACKTRACE in stacktraces, for POSIX" OFF)

if(SGNS_STACKTRACE_BACKTRACE)
    add_definitions(-DSGNS_STACKTRACE_BACKTRACE=1)
```

**Direct precedent — AsyncIOManager** (`:313-317`, verbatim; note the naming difference: `THIRDPARTY_BUILD_DIR`, NO underscore, vs SuperGenius's `_THIRDPARTY_BUILD_DIR`):
```cmake
# AsyncIOManager
set(AsyncIOManager_INCLUDE_DIR "${THIRDPARTY_BUILD_DIR}/AsyncIOManager/include")
set(AsyncIOManager_LIBRARY_DIR "${THIRDPARTY_BUILD_DIR}/AsyncIOManager/lib")
set(AsyncIOManager_DIR "${THIRDPARTY_BUILD_DIR}/AsyncIOManager/lib/cmake/AsyncIOManager")
find_package(AsyncIOManager CONFIG REQUIRED)
```

**Canonical hint style** (`:269-273` RapidJSON / `:141-145` RocksDB, verbatim):
```cmake
# RapidJSON
set(RapidJSON_DIR "${THIRDPARTY_BUILD_DIR}/rapidjson/lib/cmake/RapidJSON")
set(RapidJSON_INCLUDE_DIR "${THIRDPARTY_BUILD_DIR}/rapidjson/include")
find_package(RapidJSON CONFIG REQUIRED)
include_directories(${RapidJSON_INCLUDE_DIR})
```

**Ordering boundary — SuperGenius export consumption** (`:460-462` region, verbatim; the SDK-side block goes BEFORE these lines):
```cmake
# SuperGenius project
set(evmrelay_DIR "${SUPERGENIUS_BUILD_DIR}/SuperGenius/lib/cmake/evmrelay/")
set(SuperGenius_DIR "${SUPERGENIUS_BUILD_DIR}/SuperGenius/lib/cmake/SuperGenius/")
...
find_package(SuperGenius CONFIG REQUIRED)
```

---

### `SuperGenius/src/crdt/globaldb/globaldb.hpp` (model, transform)

**Analog:** same file — `BackupOptions` struct + trailing defaulted `New()` parameter. `ColdStorageOptions` slots in beside `BackupOptions`; `New()` gains `ColdStorageOptions cold_storage_options = ColdStorageOptions{}` after the existing defaulted param.

**Struct precedent** (`:28-34`, verbatim):
```cpp
        struct BackupOptions
        {
            bool     enabled{ false };
            uint32_t interval_minutes{ 15 };
            uint32_t keep_count{ 12 };
            bool     auto_restore_on_repair_failure{ true };
        };
```

**Factory-signature precedent** (`:53-63`, verbatim tail; every existing call site compiles unchanged when the new param is trailing-defaulted):
```cpp
        static outcome::result<std::shared_ptr<GlobalDB>> New(
            std::shared_ptr<boost::asio::io_context>                              context,
            std::string                                                           databasePath,
            std::shared_ptr<sgns::ipfs_pubsub::GossipPubSub>                      pubsub,
            std::shared_ptr<CrdtOptions>                                          crdtOptions,
            std::shared_ptr<sgns::ipfs_lite::ipfs::graphsync::Network>            graphsyncnetwork,
            std::shared_ptr<libp2p::basic::Scheduler>                             scheduler,
            std::shared_ptr<sgns::ipfs_lite::ipfs::graphsync::RequestIdGenerator> generator,
            std::shared_ptr<RocksDB>                                              datastore = nullptr,
            BackupOptions backup_options = BackupOptions{ false, 15, 12, true } );
```
Follow with a Doxygen `@param[in] cold_storage_options ...` line, matching the `@param[in] backup_options` entry at `:51`.

**Mapping target (frozen surface — do not redefine)** (`thirdparty/sgns-blockstore/include/sgns-blockstore/S3Client.hpp:58-72`): `S3ClientConfig { endpoint; port=0; region="us-east-1"; useTls=false; tlsVerify=true; pathStyle=true; accessKey; secretKey; bucket }` — `ColdStorageOptions` maps the D-02 locked subset (`endpoint, bucket, access_key, secret_key, prefix, path_style, tls`) onto it; let `port/region/tlsVerify` default.

---

### `SuperGenius/src/crdt/globaldb/globaldb.cpp` (service, transform)

**Analog:** same file — `GlobalDB::New` body. Assignment to member BEFORE `Init()` (`:86-88`, verbatim):
```cpp
        auto new_instance = std::shared_ptr<GlobalDB>(
            new GlobalDB( std::move( context ), std::move( databasePath ), std::move( pubsub ) ) );
        new_instance->backup_options_ = backup_options;

        BOOST_OUTCOME_TRY( new_instance->Init( std::move( crdtOptions ),
```
New line beside it: `new_instance->cold_storage_options_ = cold_storage_options;` (member `cold_storage_options_` declared beside `backup_options_` at `globaldb.hpp:330`). When disabled (default): construct nothing — the IpfsDatastore seam (`~:322-365`) is untouched.

---

### `SuperGenius/src/account/GeniusNode.hpp` (model, config state)

**Analog:** the `crdt_backup_config_` member (research-pinned `:1624`) and `LoadCrdtConfig` declaration (`:1383`). Add beside them: `crdt::GlobalDB::ColdStorageOptions cold_storage_config_;` (default-constructed = disabled). No other header change needed.

---

### `SuperGenius/src/account/GeniusNode.cpp` (config-loader service, file-I/O + startup)

**Analog:** same file — `LoadCrdtConfig` `:552-610` is the function being extended; `LoadLogConfig`'s member-iteration loop and the constructor's throw discipline supply the strict mechanics.

**File-level leniency to KEEP verbatim (D-06)** (`:554`, `:557-563`, `:566-571` — defaults, file-missing, parse-error):
```cpp
        crdt_backup_config_ = crdt::GlobalDB::BackupOptions{ true, 15, 12, true };
        ...
        if ( !config_file.good() )
        {
            node_logger_->info( "crdt_config.json not found at {}, using defaults", config_path );
            return;
        }
        ...
        if ( config_json.HasParseError() || !config_json.IsObject() )
        {
            node_logger_->warn( "Invalid crdt_config.json at {}, using defaults", config_path );
            return;
        }
```

**Per-member lenient shape NOT to copy for `blockstore`** (`:575-583` — this is the silent-disable anti-pattern for the new section):
```cpp
        if ( config_json.HasMember( "backup_enabled" ) && config_json["backup_enabled"].IsBool() )
        {
            crdt_backup_config_.enabled = config_json["backup_enabled"].GetBool();
        }
```

**Unknown-key detection precedent — member iteration** (`LoadLogConfig`, `:637-643`; flip warn-and-skip to collect-and-throw, and type-check each value in the same pass):
```cpp
        for ( auto it = config_json["loggers"].MemberBegin(); it != config_json["loggers"].MemberEnd(); ++it )
        {
            if ( !it->value.IsString() )
            {
```

**Loud-failure surface precedent — constructor throws** (`:358-376`, verbatim excerpt; `LoadCrdtConfig()` is called at `:376`, so a throw from the load path aborts startup exactly like these):
```cpp
        if ( !account_ )
        {
            throw std::runtime_error( "Account creation failed" ); // D-04: New() catches -> nullptr
        }
        ...
        if ( !InitNetwork( 40001, node_type_ ) )
        {
            throw std::runtime_error( "Network initialization error" );
        }
```

**Threading call site — trailing options arg** (`InitDatabase`, `:2117-2131`, verbatim):
```cpp
            auto global_db_ret = crdt::GlobalDB::New( io_,
                                                      write_base_path_ + gnus_network_full_path_,
                                                      pubsub_,
                                                      crdt::CrdtOptions::DefaultOptions(),
                                                      graphsyncnetwork_,
                                                      scheduler_,
                                                      generator_,
                                                      nullptr,
                                                      crdt_backup_config_ );
```
(8 more call sites compile unchanged — trailing-default rule. Error propagation here is log-and-break `:2129-2133`; RESEARCH recommends throwing from the load path instead, before any RocksDB work.)

**Env-read precedent** (`SuperGenius/src/coinprices/PriceEndpoints.hpp:33`): `const char *env = std::getenv( envName );` — header-only free-function accessor over `std::getenv`; the only `std::getenv` use in `SuperGenius/src`. Treat empty string as unset for D-08 (env never activates).

**Credential-logging hazard (do NOT copy):** the loaded-config info line `:602-609` prints every backup field. The new blockstore info line (only when present-and-valid) prints endpoint/bucket/prefix/path_style/tls — NEVER access_key/secret_key (matches `S3Client.hpp:68-69` field docs: "credential - never logged").

---

### `SuperGenius/test/src/crdt/cold_storage_config_gate_test.cpp` **(NEW)** (test, hermetic)

**Analog 1 — config-validation case shape (hermetic, zero network)** (`thirdparty/sgns-blockstore/test/s3_block_store_test.cpp:162-206`, verbatim test names; the tri-state matrix maps directly: valid-config-constructs / empty-endpoint-throws / empty-bucket-throws):
```cpp
// @given a valid S3ClientConfig pointing at a deliberately non-listening
// @when OpenMinioS3Client constructs the production client
TEST_F(S3BlockStoreTest, OpenMinioS3ClientConstructsWithoutNetworkIO)
...
// @given an S3ClientConfig with an empty endpoint
// @then std::invalid_argument at the factory call site (programmer error)
TEST_F(S3BlockStoreTest, OpenMinioS3ClientThrowsOnEmptyEndpoint)
```

**Analog 2 — SuperGenius-side GTest structure** (`SuperGenius/test/src/crdt/globaldb_integration.cpp:1-25`: gtest include, file-doc `@file/@brief` comment, one-time logger setup in `SetUpTestSuite`, anonymous namespace — follow this header discipline but stay lightweight; the config-gate test needs no pubsub/graphsync).

**EXPECT_THROW style** (`thirdparty/sgns-blockstore/test/memory_block_store_test.cpp:207-211`):
```cpp
    EXPECT_THROW((void)store_->Put(bad, SpanOf(payload_a_)), std::invalid_argument);
```
Test matrix per CONTEXT D-03..D-08: absent section / all-blank ⇒ disabled & no-new-log-line; partial ⇒ throw naming missing field; unknown key ⇒ throw naming key; wrong type ⇒ throw; env override satisfies credentials only; env + blank config ⇒ still disabled; captured output contains no credential substring. Note: the library's `InMemoryS3Client` is src-only (NOT installed) — for any S3Client-level fake, implement the installed `S3Client` interface (`S3Client.hpp:146-192`) in-test, or use `MemoryBlockStore`; for Phase 7's config-gate scope the real `OpenMinioS3Client` (eager validation, zero network I/O) may suffice.

---

### `SuperGenius/test/src/crdt/CMakeLists.txt` (test config)

**Analog 1 — same-file registration** (`:1-9` + `:36-38`, verbatim):
```cmake
addtest(crdt_test
    crdt_hierarchical_key_test.cpp
    ...
)
...
addtest(globaldb_integration_test
    globaldb_integration.cpp
)
```

**Analog 2 — LABELS convention to transplant** (`thirdparty/sgns-blockstore/test/CMakeLists.txt:10-17`, verbatim incl. the D-13 rationale comment; SuperGenius's `addtest()` — `SuperGenius/cmake/functions.cmake:8-38` — has NO LABELS support, so the `set_tests_properties` line is mandatory, not optional):
```cmake
addtest(memory_block_store_test memory_block_store_test.cpp)
target_link_libraries(memory_block_store_test
    sgns-blockstore
    p2p::p2p_cid
)
# D-13 (Phase 5): every registration carries its tier LABEL - the tier
# assignment of each test is readable from this file without running
# anything; CI selects the hermetic lane with a fail-closed -L Tier1.
set_tests_properties(memory_block_store_test PROPERTIES LABELS "Tier1")
```
New registration: `addtest(cold_storage_config_gate_test cold_storage_config_gate_test.cpp)` + `target_link_libraries(cold_storage_config_gate_test crdt_globaldb)` (rapidjson arrives PRIVATE through `crdt_globaldb` — `SuperGenius/src/crdt/globaldb/CMakeLists.txt:21`) + `set_tests_properties(... PROPERTIES LABELS "Tier1")`. Register UNCONDITIONALLY (parse/env code compiles unconditionally — Pitfall 6: `--no-tests=error` fails an empty label selection in default OFF builds).

---

### `GeniusWallet/assets/crdt_config.json` (config asset)

**Analog:** same file — current verbatim content (the flat `backup_*` keys stay untouched):
```json
{
  "backup_enabled": true,
  "backup_interval_minutes": 15,
  "backup_keep_count": 12,
  "backup_auto_restore_on_repair_failure": true
}
```
**Nested-object shape precedent** (`GeniusWallet/assets/log_config.json:1-5`): `{ "loggers": { "SuperGeniusNode": "trace", ... } }` — the only nested-object config asset; the `blockstore` section follows this nesting depth. Parity shape (omit entirely vs `"blockstore": {}`) is agent discretion per CONTEXT.

---

### `GeniusWallet/lib/settings/settings_screen.dart` (component, load→edit→save roundtrip)

**Analog:** same file — the Network section's whitelist filter (`:130-137`, verbatim):
```dart
  Future<void> _loadNetworkConfig() async {
    setState(() => _networkLoading = true);
    final json = await _readSdkJson('network_config.json');
    final whitelist = _api.networkConfigOverrideKeys;
    _networkConfig = Map.fromEntries(
      json.entries.where((e) => whitelist.contains(e.key)),
    );
    setState(() => _networkLoading = false);
  }
```

**The hazard being fixed** (`_configFieldsTable`, `:382-437`; renders EVERY map entry, writes edited strings back — a nested `blockstore` Map would be stringified by `initialValue: entry.value.toString()` and clobbered by `config[entry.key] = v`):
```dart
      children: config.entries.map((entry) {
        final label = keyLabels[entry.key] ?? entry.key;
        ...
              child: GWTextField(
                initialValue: entry.value.toString(),
                ...
                  } else {
                    setState(() => config[entry.key] = v);
```
**Fix shape:** filter to known keys at the CRDT call site (`:294-303` passes `keyLabels: const {...}` / `boolKeys: const {...}`) — `config.entries.where((e) => keyLabels.containsKey(e.key))` — so unknown/nested entries round-trip untouched through `_loadCrdtConfig` (`:148-152`) → `_saveCrdtConfig` (`:154-160` → `_writeOverrides` `:90-100`).

---

### `SuperGenius/.github/workflows/cmake.yml` (CI config) — partial analog

**Analog:** same file — the existing ctest step (`:604`, verbatim; also `:674-676`) is fail-OPEN for unlabeled tests (`-LE` excludes labeled, runs everything else). The Tier-1 lane is a SEPARATE explicit invocation, not a modification of this line:
```yaml
        run: ctest . -j ${{ env.CTEST_JOBS }} -C ${{ matrix.build-type }} --output-on-failure -LE requires_foundry
```
**Lane-command precedent** (`thirdparty/sgns-blockstore/docs/testing-tiers.md:55`, verbatim — the fail-closed invocation to add as a new step/job after `:604`):
```
ctest --test-dir sgns-blockstore/src/sgns-blockstore-build -C <type> --output-on-failure -L Tier1 --no-tests=error
```
`-L` never includes unlabeled tests; `--no-tests=error` fails an empty selection (label typo cannot pass vacuously). Configure line consuming `THIRDPARTY_BUILD_DIR` at `:523`; tarball download at `:328` (ON-lane prerequisite — see Pitfall 10/A3 in RESEARCH).

---

### `supergenius-sharded-ipld-cache-architecture.md` (docs, D-10 M3 posture)

**Analog:** same file — "Example runtime configuration" `:500-539` is the neighboring ops content (verbatim tail; the credentials sentence is the D-07 anchor already in the doc):
```markdown
Credentials should come from environment variables, protected secret files, or an external secret manager rather than the main configuration file.
```
New ops/runbook section (cold journal = rebuildable, re-drain → CID-verified rebuild from S3 listing) lands near the ops-adjacent sections: "Key risks" `:607`, "Open design questions" `:633`, "Planning recommendation" `:649`. Follow the existing `##`/`###` heading discipline and the doc's prose+list style. Cite from this phase so the Phase-11 planner inherits it (CONTEXT D-10).

---

## Shared Patterns

### 1. Install-tree find_package consumption (unversioned, hint + CONFIG REQUIRED)
**Source:** `SuperGenius/build/CommonBuildParameters.cmake:118-121,406-409`; `GeniusSDK/cmake/CommonBuildParameters.cmake:269-273,313-317`; `thirdparty/sgns-blockstore/test/out_of_tree_consumer/CMakeLists.txt:19-33`
**Apply to:** both `CommonBuildParameters.cmake` blocks. Never a version argument (dual-RocksDB compat), never `add_subdirectory`, never inside the libssh2 `PREFER_CONFIG` window, `httplib` explicitly first, hints via `*_DIR` variables (or `CMAKE_PREFIX_PATH` — never dotted `-D` cache names).

### 2. OFF-by-default option gating
**Source:** `GeniusSDK/cmake/CommonBuildParameters.cmake:205-212` (`option(SGNS_STACKTRACE_BACKTRACE ... OFF)` + `if()` body)
**Apply to:** `option(SGNS_COLD_STORAGE ... OFF)` in BOTH cmake files. No in-repo `IOS/ANDROID` FORCE-off precedent exists — extend with the standard `set(... CACHE BOOL ... FORCE)` idiom (flagged under No Analog).

### 3. Config-load leniency boundary (file-level lenient / section-level strict)
**Source:** `SuperGenius/src/account/GeniusNode.cpp:557-571` (keep verbatim) + `:358-376` (throw discipline)
**Apply to:** the `blockstore` extension of `LoadCrdtConfig`. File missing/corrupt ⇒ existing warn+return path untouched (D-06); section present-but-malformed ⇒ `throw std::runtime_error` naming the field/key (D-04/D-05) — surfaces through the constructor path that already throws.

### 4. Unknown-key detection via one member-iteration pass
**Source:** `SuperGenius/src/account/GeniusNode.cpp:637-643` (`LoadLogConfig` loop)
**Apply to:** the `blockstore` object parser — same `MemberBegin()/MemberEnd()` shape, collect-then-fail instead of warn-and-skip, type-check each known key in the same pass.

### 5. Trailing-defaulted struct parameter threading
**Source:** `SuperGenius/src/crdt/globaldb/globaldb.hpp:54-63` + `globaldb.cpp:86-88` (`BackupOptions`)
**Apply to:** `ColdStorageOptions` through `GlobalDB::New` — trailing defaulted param, member assigned before `Init()`, all 9 existing call sites (`GeniusNode.cpp:2119` + `GlobalDbNetworkComposition.cpp:225` + five migration files + default-arg callers) compile unchanged.

### 6. Tier-1 label registration + fail-closed lane
**Source:** `thirdparty/sgns-blockstore/test/CMakeLists.txt:10-17`; `thirdparty/sgns-blockstore/docs/testing-tiers.md:55`; `SuperGenius/cmake/functions.cmake:8-38` (`addtest()`, no LABELS arg)
**Apply to:** every new SuperGenius test registration — `addtest(...)` + mandatory `set_tests_properties(<t> PROPERTIES LABELS "Tier1")`; lane = `ctest -L Tier1 --no-tests=error` as a separate CI invocation. Tier-audit tripwire pattern: `tier1_static_audit` (testing-tiers.md:25) — registration-vs-label count guard.

### 7. Credentials never logged (redaction by omission)
**Source:** `thirdparty/sgns-blockstore/include/sgns-blockstore/S3Client.hpp:68-69` ("credential - never logged" field docs), `:197-211` (factory contract)
**Apply to:** every log line the new code emits — endpoint/bucket/prefix/path_style/tls only; never format `access_key`/`secret_key` into any string. Contrast hazard: `GeniusNode.cpp:602-609` prints every backup field today — do not extend that shape.

### 8. Wallet whitelist filter for config editors
**Source:** `GeniusWallet/lib/settings/settings_screen.dart:130-137`
**Apply to:** the CRDT section editor (`:294-303` call site) — filter to `keyLabels`-known keys so nested objects survive the load→edit→save roundtrip (`_writeOverrides` `:90-100`).

## No Analog Found

| File / Sub-pattern | Role | Data Flow | Reason |
|------|------|-----------|--------|
| Strict tri-state section parser (partial-fill ⇒ throw) in `GeniusNode.cpp` | config parser | file-I/O | Every in-repo loader (`LoadCrdtConfig`, `LoadSgnsConfig`, `LoadLogConfig`) is per-member lenient warn-and-continue. Compose from Shared Patterns 3+4 + ctor-throw discipline; RESEARCH Code Example §1 is the approved sketch. |
| Fail-closed `-L Tier1` CI step in `SuperGenius/.github/workflows/cmake.yml` | CI config | batch | SuperGenius CI is fail-open (`-LE requires_foundry`, `:604`/`:674-676`). Only precedent is the documented library lane command (testing-tiers.md:55) — new step/job, do not modify the existing lane. |
| `IOS OR ANDROID` → FORCE-off gate for `SGNS_COLD_STORAGE` | build config | — | No mobile-conditional option force exists in either `CommonBuildParameters.cmake`. Use the standard `set(<VAR> OFF CACHE BOOL "" FORCE)` idiom inside `if(IOS OR ANDROID)`. |
| `InMemoryS3Client` fake reuse on the SuperGenius side | test fake | — | The fake is src-only (NOT installed — `include/sgns-blockstore/` listing). If a client-level fake is needed, implement the installed `S3Client` interface (`S3Client.hpp:146-192`) in-test; Phase 7's config-gate scope is covered by the real `OpenMinioS3Client` (eager validation, zero network I/O at construction). |

## Metadata

**Analog search scope:** `SuperGenius/{build,cmake,src/account,src/crdt/globaldb,test,.github/workflows}`, `GeniusSDK/cmake`, `GeniusWallet/{assets,lib/settings}`, `thirdparty/sgns-blockstore/{include,test,docs}`, workspace root doc
**Files scanned:** ~25 read/grepped in-tree this session; every cited line number verified against the working tree (2026-10-23)
**Tracked-source gate:** all analog paths passed `git ls-files` in their owning repo/submodule (root: `supergenius-sharded-ipld-cache-architecture.md`; SuperGenius: 7 paths; GeniusSDK: 1; GeniusWallet: 2; thirdparty/sgns-blockstore nested: 5)
**Pattern extraction date:** 2026-10-23
