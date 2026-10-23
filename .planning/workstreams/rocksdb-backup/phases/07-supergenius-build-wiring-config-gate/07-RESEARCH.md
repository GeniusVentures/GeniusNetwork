# Phase 7: SuperGenius Build Wiring & Config Gate - Research

**Researched:** 2026-10-23
**Domain:** CMake install-tree consumption of a superbuild static library into the SuperGenius/GeniusSDK builds; strict tri-state JSON config gating; hermetic Tier-1 test-lane transplant (C++17/CMake, no new external dependencies)
**Confidence:** HIGH (every CMake/config/test seam read in-tree this session with file:line cites); MEDIUM on CI-runner specifics and the thirdparty release-tarball question (flagged in Open Questions)

## Summary

Phase 7 is pure consumer-side wiring: no library changes, no new dependencies. Three seams were verified in-tree this session. **(1) Build wiring** — both `CommonBuildParameters.cmake` files already have the exact precedent SC1 asks for (explicit `*_DIR` hint + `find_package(... CONFIG REQUIRED)`, placed after the libssh2 `PREFER_CONFIG` window: `SuperGenius/build/CommonBuildParameters.cmake:392` starts the window, `:408-409` is the AsyncIOManager consumption block that sits safely outside it; `GeniusSDK/cmake/CommonBuildParameters.cmake:291-311` window, `:313-317` AsyncIOManager). The Phase-6-hardened package config (`thirdparty/sgns-blockstore/cmake/config.cmake.in` now runs `find_dependency` for RocksDB, libp2p, ipfs-lite-cpp, miniocpp) plus the out-of-tree consumer proof (`thirdparty/sgns-blockstore/test/out_of_tree_consumer/`) reduce the new block to: set hints for `httplib`/`miniocpp`/`pugixml`(/`nlohmann_json` on the SDK side), `find_package(httplib CONFIG REQUIRED)` first (the Phase-3 QUIET-find trap), then `find_package(miniocpp CONFIG REQUIRED)`, then `find_package(sgns-blockstore CONFIG REQUIRED)`. A subtlety the planner must not miss: **GeniusSDK consumes the SuperGenius install tree as an exported package** (`find_package(SuperGenius CONFIG REQUIRED)` at `GeniusSDK/cmake/CommonBuildParameters.cmake:462`), so the SDK-side sgns-blockstore find must land **before** that line once any SuperGenius export references the target. **(2) Config gate** — `GeniusNode::LoadCrdtConfig` (`SuperGenius/src/account/GeniusNode.cpp:552-610`) is fully lenient today (warn + defaults on file-level failure, per-member `HasMember&&Is*` guards); D-03..D-06 layer strict tri-state semantics on a *nested* `blockstore` object while keeping the file-level leniency. `GlobalDB::New` already demonstrates the exact threading mechanism: a trailing defaulted struct parameter assigned to a member before `Init()` (`globaldb.hpp:54-63`, `globaldb.cpp:86-88` — 8 existing call sites keep compiling). **(3) Tier-1 lane** — SuperGenius's `addtest()` (`SuperGenius/cmake/functions.cmake:8-38`) registers tests with **no LABELS today**; the transplant is `set_tests_properties(<t> PROPERTIES LABELS "Tier1")` after `addtest`, plus the fail-closed `ctest -L Tier1 --no-tests=error` invocation documented in `thirdparty/sgns-blockstore/docs/testing-tiers.md`.

Two research discoveries reshape planning assumptions. First, the **"dual RocksDB 9.4/11.1 in one binary" phrasing needs reinterpretation**: the tree pins exactly one RocksDB (`#define ROCKSDB_MAJOR 9 / ROCKSDB_MINOR 4 / ROCKSDB_PATCH 0`, `thirdparty/rocksdb/include/rocksdb/version.h`, read this session) and both SuperGenius and sgns-blockstore resolve the *same* install tree — the "dual" is the library's dual-**compat** posture (unversioned `find_package(RocksDB CONFIG)`; standalone builds verified against 11.1.2). The real proof obligation is: no version pin on any consumer find, no second RocksDB archive entering the link, and one clean three-platform link. Second, the **GeniusWallet Settings screen will corrupt a nested `blockstore` object**: `_configFieldsTable` (`GeniusWallet/lib/settings/settings_screen.dart:383-437`) renders *every* map entry as a text field and writes the edited string back into the JSON map — a user edit+save of the blockstore row would stringify the object and trip the node's malformed=loud contract at next start. The wallet-parity task must filter the table to known keys (the Network section already does exactly this via a whitelist, `:130-134`).

**Primary recommendation:** Gate the whole consumption block behind `option(SGNS_COLD_STORAGE ... OFF)` in both CMake files (force OFF on iOS/Android), keep the `ColdStorageOptions` struct + strict parsing + env resolution compiled **unconditionally** (they need only rapidjson, and the config-gate Tier-1 tests then always register, keeping `--no-tests=error` green in default OFF builds), thread options through `GlobalDB::New` as a trailing defaulted parameter exactly like `BackupOptions`, and surface malformed-config as a `std::runtime_error` from the `GeniusNode` init path (the constructor already throws there — `GeniusNode.cpp:358-369`).

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Config section shape & naming**
- **D-01:** The cold-storage section is a **nested `blockstore` object** in `crdt_config.json` — the backend-agnostic capability name (not `s3d.*`, not flat `blockstore_*` keys). INTG-02's own wording; future knobs (retention in Phase 11, backpressure in Phase 8) nest cleanly under it. Canonical across node config, `GeniusWallet/assets/crdt_config.json`, docs, and the `SGNS_BLOCKSTORE_S3_*` env prefix — **Reversibility:** costly — the section name binds the shipped config schema, the wallet asset, env-var naming, and operator docs; renaming after configs are written in the field is a breaking schema change
- **D-02:** S3 fields sit **directly under `blockstore`** (`endpoint`, `bucket`, `access_key`, `secret_key`; optional `prefix`, `path_style`, `tls`) — no `s3` sub-object. One backend exists in v1.1; simplest parse and simplest wallet-asset parity — **Reversibility:** costly — config field paths bind the node parser, wallet asset, and docs; inserting an `s3` level later is a schema migration

**Tri-state semantics (INTG-02 contract, fully specified)**
- **D-03:** **Absent section or all-required-fields-blank ⇒ disabled, byte-identical to today** — no blockstore constructed, no new code paths taken (the SC2 bar)
- **D-04:** **Partially-filled section ⇒ loud startup failure naming the missing field** — any required field filled while another required field is blank/missing signals intent to enable; silently disabling it is exactly the silent-disable failure INTG-02 forbids
- **D-05:** **Unknown keys inside `blockstore` ⇒ loud startup failure naming the key** — catches `"acess_key"`-style typos at startup instead of as confusing auth failures at first drain (Phase 8+); the strict-typo posture follows from malformed=loud
- **D-06:** **Whole-file JSON parse failure keeps the legacy lenient behavior** — warn + defaults for the existing backup keys; the blockstore section is treated as absent ⇒ disabled. The loud contract applies only when the section is inspectable; this preserves byte-identical behavior for existing deployments running corrupt configs — **Reversibility (D-03..D-06):** costly — these semantics are the operator contract proven by the config-gate hermetic tests (SC2/SC3 evidence binds them); loosening any edge after publication breaks the fail-loud guarantee

**Env override surface**
- **D-07:** **Credentials only** — exactly two env vars exist: `SGNS_BLOCKSTORE_S3_ACCESS_KEY`, `SGNS_BLOCKSTORE_S3_SECRET_KEY`. Endpoint/bucket/tls/prefix come solely from the config file. Credentials-in-env matches the k8s secret-injection pattern, which is where env overrides earn their keep
- **D-08:** **Env never activates** — env vars override credential *values* but the `blockstore` config section is the only activation switch; a blank/absent section stays disabled regardless of environment. Keeps the SC2 byte-identical bar airtight (a stray exported env var can never change node behavior) and keeps the config-gate test matrix small — **Reversibility:** costly — the blank-config byte-identical claim (SC2) is stated over this rule; adding an env-activation path later invalidates the guarantee for every blank-config deployment

**M3 cold-journal backup posture**
- **D-09:** **The cold journal is declared rebuildable** — not backed up. Recovery semantics: re-drain pending uploads as-is first; where a gap exists (journal older than a restored GlobalDB ⇒ blocks never marked for upload ⇒ silent cold-store gap), rebuild from a CID-verified diff of hot-store CIDs vs the S3 remote listing. Relies on the library's idempotent createOnly + CID-verify contracts; S3 is already the system of record for cold data. Zero backup-engine surface (consistent with the milestone-wide out-of-scope boundary on `globaldb.cpp` backup-path changes). The rebuild tooling itself lands in Phase 11 — **Reversibility:** reversible — a documented posture; switching to co-scheduled backup later adds tooling without unwinding anything shipped
- **D-10:** **Documented in the architecture doc** — the M3 decision + rebuild semantics land in `supergenius-sharded-ipld-cache-architecture.md` (ops/runbook section), cited from this CONTEXT so the Phase 11 planner inherits it. No code in Phase 7

### The Agent's Discretion
- Exact CMake mechanics inside the consumption block (hint variable names, ordering details) following the AsyncIOManager precedent at `SuperGenius/build/CommonBuildParameters.cmake:406` / `GeniusSDK/cmake/CommonBuildParameters.cmake:313`
- How `SGNS_COLD_STORAGE` gates compilation (conditional source inclusion vs preprocessor guards) — planner's call
- Where the loud failure surfaces (`GeniusNode` init vs `GlobalDB::New` error propagation) as long as startup fails loudly with a precise message
- `ColdStorageOptions` struct shape and threading mechanics through `GlobalDB::New`
- Test registration mechanics for the SuperGenius Tier-1 lane (target location, `addtest()`, label wiring, tier-audit) per v1.0 patterns
- Exact error-message wording (constraint: must name the missing field / unknown key)
- Wallet-asset parity shape: omit the section entirely vs ship `"blockstore": {}` — both are blank/absent per D-03; planner picks
- Whether `path_style`/`tls` defaults come from `S3ClientConfig` defaults or are set explicitly

### Deferred Ideas (OUT OF SCOPE)
- M3 rebuild tooling (rebuild-from-remote-listing command) — Phase 11 (with GC, which is its consumer)
- Mobile superbuild legs (iOS/Android sgns-blockstore install trees) — Future requirement; `SGNS_COLD_STORAGE` stays OFF on mobile until verified
- Full env-override surface (endpoint/bucket via env) and env-only activation — explicitly **rejected** in D-07/D-08, not deferred; revisit only with a concrete container-deployment requirement
- Metrics surface for the gate (config-load telemetry) — the milestone's Future metrics list

### Reviewed Todos (not folded)
- `2026-08-10-fix-vulkan-capability-probe-deadlock-in-processingmanager-cr.md` — ruled unrelated to the blockstore workstream in Phase 6's discussion — stays a backlog todo
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| INTG-01 | SuperGenius and GeniusSDK resolve sgns-blockstore via `find_package(sgns-blockstore CONFIG REQUIRED)` against the superbuild install tree in both `CommonBuildParameters.cmake` files (ordered after the miniocpp dependency chain), linking `sgns-blockstore::sgns-blockstore` on all desktop platforms | Consumption-block pattern with exact placements, hint closure, and ordering constraints (Architecture Patterns §1, Code Examples §1); `SGNS_COLD_STORAGE` gating design (§2); GeniusSDK-before-`find_package(SuperGenius)` ordering discovery (Pitfall 4); dual-RocksDB reinterpretation with `version.h` evidence (Pitfall 5) |
| INTG-02 | `crdt_config.json` gains a blockstore section — blank or absent ⇒ blockstore not constructed, behavior byte-identical to today; malformed ⇒ loud startup failure (never silent disable); `SGNS_BLOCKSTORE_S3_ACCESS_KEY`/`_SECRET_KEY` env vars take precedence; credentials never logged | `LoadCrdtConfig` verbatim current state + the lenient/citizen boundary (§3); strict tri-state parse mechanics with rapidjson member iteration precedent (§3, Code Examples §2); `GlobalDB::New` threading precedent (§4); env + redaction design (§5); wallet parity + round-trip corruption hazard (§6) |
| TEST-01 | Hermetic Tier-1 integration tests (InMemoryS3Client fake; config-gate, spill, fallback, GC paths) run in the fail-closed CI lane on all platforms — no Docker, no live endpoints | Tier-label transplant mechanics + fail-closed lane semantics (§7); the "fake" reality check — installed `S3Client` interface vs src-only `InMemoryS3Client` (§7, Don't-Hand-Roll); `--no-tests=error` × OFF-by-default interaction (Pitfall 6); existing CI `-LE requires_foundry` lane analysis (§7) |
</phase_requirements>

## Project Constraints (from AGENTS.md)

- **Tech stack:** C++17/C++20, CMake, libp2p, Protocol Buffers — must match existing SuperGenius conventions. The library sets `CMAKE_CXX_STANDARD 17` (`thirdparty/sgns-blockstore/CMakeLists.txt:6-8`); SuperGenius sets C++17 in `build/CommonCompilerOptions.cmake` — no 20-ism may cross installed headers.
- **Coding standard:** Corelinux-derived style per `Coding Standards.md` — Ullman braces, PascalCase types, `m_`/trailing-underscore members, Doxygen `@brief/@param/@return` on public interfaces, `outcome::result<T>` for fallible operations.
- **Build system convention (critical):** main projects have **no root CMakeLists.txt**; builds originate from `build/<Platform>/<Debug|Release>/`. All verification commands run inside those build trees (`.planning/codebase/TESTING.md`).
- **Compatibility:** proposed changes must not break existing SuperGenius, GeniusSDK, or GeniusWallet builds on any supported platform — this is why the option is OFF by default and why mobile stays OFF.
- **Security:** main-wallet private key never enters child processes; compromise bounded — not directly Phase 7's surface, but the credentials-never-logged rule (INTG-02) carries the same posture.
- **GSD workflow note:** changes span three submodules (`SuperGenius`, `GeniusSDK`, `GeniusWallet`) plus the root repo (architecture doc, planning artifacts) — commits must land inside each submodule, then pointer bumps in the parent (verified: root `.gitmodules` lists all of them; `thirdparty/sgns-blockstore` is itself a nested submodule of `thirdparty` and needs **no** Phase 7 edits).

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Dependency resolution (`find_package` install-tree consumption) | Build system (`CommonBuildParameters.cmake` ×2) | thirdparty superbuild (produces the install tree) | CMake configure-time concern; the superbuild is upstream and untouched in this phase |
| Option gating (`SGNS_COLD_STORAGE`) | Build system | — | Compile/link selection is a configure-time decision; mobile OFF enforcement lives here |
| Config parsing (strict tri-state `blockstore` section) | Node application layer (`GeniusNode::LoadCrdtConfig`) | — | `crdt_config.json` is a node-operator file loaded at node init; wallet only *ships* a template |
| Env-credential resolution | Node application layer | OS process environment | `std::getenv` read at config-load time; precedence over file values |
| Cold-storage construction (deferred behavior) | CRDT/storage layer (`GlobalDB::New`) | — | `ColdStorageOptions` threads to the datastore seam; Phase 7 wires the pipe, constructs nothing when disabled |
| Loud failure surfacing | Node application layer (GeniusNode init) | CRDT layer (`GlobalDB::New` error propagation) | Either satisfies the contract (agent discretion); constructor already throws `std::runtime_error` |
| Tier-1 test lane | Test infrastructure (`SuperGenius/test/` + `addtest`) | CI workflow | Labels + fail-closed ctest invocation; CI runs it on all platforms |
| Config schema parity | Wallet asset layer (`GeniusWallet/assets/`) | Wallet UI (`settings_screen.dart`) | The asset ships the schema; the settings editor must not corrupt it |
| M3 posture documentation | Docs (architecture doc, root repo) | — | D-10: ops/runbook section only, no code |

## Standard Stack

### Core

| Component | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| `sgns-blockstore::sgns-blockstore` (imported target) | 1.0.0 + Phase-6 additions (`VERSION 1.0.0 COMPATIBILITY AnyNewerVersion`, `thirdparty/sgns-blockstore/CMakeLists.txt:95-99`) | The cold-storage library being consumed | It is the milestone's own deliverable; namespaced export (`CMakeLists.txt:73-77`) — deliberately better than the un-namespaced AsyncIOManager precedent |
| CMake `find_package(... CONFIG REQUIRED)` + explicit `*_DIR` hints | CMake ≥ 3.22 (SuperGenius platform entry floor, `build/Windows/CMakeLists.txt:1`) | Resolve the superbuild install tree | How every existing dep is consumed — RocksDB at `SuperGenius/build/CommonBuildParameters.cmake:119-120`, AsyncIOManager at `:408-409` |
| rapidjson (already linked via `crdt_globaldb` PRIVATE) | existing | Parse the `blockstore` section | `LoadCrdtConfig` and `LoadLogConfig` already use it; `RAPIDJSON_HAS_STDSTRING=1` is defined globally (`SuperGenius/build/CommonBuildParameters.cmake:381`) |
| GTest via `addtest()` (GTest::gtest_main + gmock_main) | existing | Config-gate Tier-1 tests | `SuperGenius/cmake/functions.cmake:8-38`; every SuperGenius test uses it |

### Supporting

| Component | Already in consumer builds? | Role in Phase 7 |
|-----------|------------------------------|------------------|
| libp2p (`p2p::p2p_cid`) | Yes — `SuperGenius/.../CommonBuildParameters.cmake` libp2p find precedes the insertion point | PUBLIC dep of the sgns-blockstore export; must already be found before `find_package(sgns-blockstore)` |
| RocksDB (9.4.0 superbuild tree) | Yes — `SuperGenius/...:119-120`, `GeniusSDK/...:142-144` | PUBLIC dep of the export; the consumer's own find already satisfies it — **never add a version argument** |
| httplib / miniocpp / pugixml / nlohmann_json | No (SuperGenius) / partially (GeniusSDK: nlohmann_json at `:417-418`) | NEW hints required for the chain; nlohmann_json already found on both sides (`SuperGenius/...:486-487`, `GeniusSDK/...:417-418`) |
| `OpenMinioS3Client` + `S3ClientConfig` (installed) | Installed since Phase 6 | What `ColdStorageOptions` ultimately maps onto; eager validation + zero network I/O at construction makes even the "valid config constructs" test hermetic |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `find_package(sgns-blockstore CONFIG REQUIRED)` against install tree | `add_subdirectory(thirdparty/sgns-blockstore)` | Never — recompiles per consumer, drags miniocpp's configure-time clone into every SuperGenius configure, bypasses the superbuild's tested single build |
| Versioned `find_package(sgns-blockstore 1.0 CONFIG)` | unversioned | Keep unversioned — `AnyNewerVersion` makes versions harmless but useless, and a versioned RocksDB request would be actively harmful (dual-compat) |
| Preprocessor `#if SGNS_COLD_STORAGE` guards | conditional target/source inclusion | Agent discretion; conditional inclusion keeps ungated code (options struct + parsing) compiling and testable in default OFF builds — recommended (see Pitfall 6) |

**Installation:** none — no new packages. The thirdparty superbuild already produces every install tree consumed here (verified present on this machine: `thirdparty/build/Windows/Debug/{sgns-blockstore,minio-cpp}/lib/cmake/...`, `json/share/cmake/nlohmann_json`, `pugixml/lib/cmake/pugixml`).

## Package Legitimacy Audit

**No external packages are installed by this phase.** Every consumed artifact is produced in-repo by the thirdparty superbuild (minio-cpp, pugixml, json, sgns-blockstore are nested submodules of `thirdparty`, verified via `thirdparty/.gitmodules` this session). The v1.1 REQUIREMENTS Out-of-Scope table explicitly rejects new external dependencies. No registry lookups were needed; nothing to flag.

## Architecture Patterns

### System Architecture Diagram

```mermaid
flowchart TD
    subgraph Superbuild["thirdparty superbuild (Phase 6, untouched)"]
        EP[minio-cpp / pugixml / json / rocksdb 9.4 / libp2p / ipfs-lite-cpp] --> INSTALL[install trees under<br/>thirdparty/build/&lt;Platform&gt;/&lt;Config&gt;]
    end

    subgraph SG["SuperGenius build (build/CommonBuildParameters.cmake)"]
        OPT1{SGNS_COLD_STORAGE?} -->|OFF (default)| SGPLAIN[configure exactly as today<br/>no new finds, no new targets]
        OPT1 -->|ON / desktop| HINTS1[set *_DIR hints:<br/>httplib, miniocpp, pugixml, sgns-blockstore]
        HINTS1 --> F1[find_package httplib CONFIG REQUIRED]
        F1 --> F2[find_package miniocpp CONFIG REQUIRED]
        F2 --> F3[find_package sgns-blockstore CONFIG REQUIRED<br/>outside libssh2 PREFER_CONFIG window]
        F3 --> COLD[cold-store code links<br/>sgns-blockstore::sgns-blockstore]
    end

    subgraph Node["SuperGenius node runtime"]
        CFG[crdt_config.json] --> LOAD[LoadCrdtConfig strict tri-state parse]
        ENV[SGNS_BLOCKSTORE_S3_ACCESS_KEY / _SECRET_KEY] -->|credential values only, never activates| LOAD
        LOAD -->|absent / all-blank| OFF2[no blockstore constructed<br/>byte-identical behavior]
        LOAD -->|partial / unknown key / wrong type| FAIL[loud startup failure<br/>names field or key]
        LOAD -->|complete| CSO[ColdStorageOptions]
        CSO --> GDB[GlobalDB::New trailing param<br/>→ member, like BackupOptions]
        GDB -->|disabled| SEAM[IpfsDatastore seam unchanged<br/>globaldb.cpp ~:329]
    end

    subgraph Tests["Tier-1 lane (fail-closed)"]
        T1[config-gate tests<br/>blank/absent/malformed/env-override/redaction] -->|LABELS Tier1| CTEST[ctest -L Tier1 --no-tests=error]
    end

    subgraph Wallet["GeniusWallet"]
        ASSET[assets/crdt_config.json<br/>schema parity] --> SDKDIR[SDK config dir via prepareConfigFiles]
        SETTINGS[settings_screen.dart] -->|must not corrupt nested object| SDKDIR
    end

    INSTALL --> HINTS1
    COLD --> SEAM
```

### Recommended Project Structure

```
SuperGenius/
├── build/CommonBuildParameters.cmake      # gated consumption block (~after line 409)
├── src/account/GeniusNode.{hpp,cpp}       # ColdStorageOptions member + strict parse + env + loud failure
├── src/crdt/globaldb/globaldb.{hpp,cpp}   # New() trailing param; construct-nothing-when-disabled
├── test/src/crdt/                          # config-gate Tier-1 test target (crdt_test dir precedent)
GeniusSDK/
├── cmake/CommonBuildParameters.cmake      # mirrored block (before find_package(SuperGenius) :462)
GeniusWallet/
├── assets/crdt_config.json                # schema parity (omit section OR "blockstore": {})
├── lib/settings/settings_screen.dart      # whitelist-filter the CRDT editor
supergenius-sharded-ipld-cache-architecture.md  # M3 ops/runbook section (D-10)
```

### Pattern 1: The gated consumption block (INTG-01)

**What:** one self-contained CMake block per file, mirroring the superbuild's own hint closure.
**When to use:** both `CommonBuildParameters.cmake` files, desktop-only.
**Placement (verified this session):**
- SuperGenius: after `:408-409` (AsyncIOManager) — i.e., after the libssh2 `PREFER_CONFIG` window that starts at `:392` and restores at `:398-405`. Do **not** place inside the window.
- GeniusSDK: after `:322` (`gnus_upnp_DIR`) or anywhere before `:462` (`find_package(SuperGenius CONFIG REQUIRED)`) — see Pitfall 4 for why the SDK-side ordering constraint is *before the SuperGenius find*, not merely "after libp2p/RocksDB".

```cmake
# Source: adapted from v1.1 STACK research (2026-10-22) + Phase-6 consumer-proof
# hint closure (thirdparty/sgns-blockstore/test/out_of_tree_consumer/run_consumer_proof.cmake:59-105)
option(SGNS_COLD_STORAGE "Link sgns-blockstore cold-storage tiers (desktop only)" OFF)
if(IOS OR ANDROID)
    set(SGNS_COLD_STORAGE OFF CACHE BOOL "Cold storage unsupported on mobile until install trees verified" FORCE)
endif()
if(SGNS_COLD_STORAGE)
    # Order matters: miniocpp's consumer config re-runs miniocpp-deps.cmake in THIS
    # context, so pugixml/nlohmann_json/httplib must resolve here too; httplib must
    # be found EXPLICITLY first (Phase-3 spike finding — its QUIET sub-find does not
    # register the target for imported-target verification).
    set(pugixml_DIR         "${_THIRDPARTY_BUILD_DIR}/pugixml/lib/cmake/pugixml")
    set(nlohmann_json_DIR   "${_THIRDPARTY_BUILD_DIR}/json/share/cmake/nlohmann_json")  # GNUInstallDirs datadir, NOT lib/cmake
    set(httplib_DIR         "${_THIRDPARTY_BUILD_DIR}/minio-cpp/lib/cmake/httplib")
    set(miniocpp_DIR        "${_THIRDPARTY_BUILD_DIR}/minio-cpp/lib/cmake/miniocpp")
    find_package(httplib CONFIG REQUIRED)
    find_package(miniocpp CONFIG REQUIRED)
    set(sgns-blockstore_DIR "${_THIRDPARTY_BUILD_DIR}/sgns-blockstore/lib/cmake/sgns-blockstore")
    find_package(sgns-blockstore CONFIG REQUIRED)
endif()
```

GeniusSDK variant: same block with `THIRDPARTY_BUILD_DIR` (no underscore — that variant's naming, e.g. `:142`). The Phase-6-hardened `config.cmake.in` (`find_dependency` for RocksDB, libp2p, ipfs-lite-cpp, miniocpp) makes the block smaller than v1.0 planning assumed — the explicit `find_package(miniocpp)` is belt-and-braces ordering clarity, matching the library's own root `CMakeLists.txt:33-63` ordering (httplib explicitly, then miniocpp, then ipfs-lite-cpp).

**Why gated:** P12 trap 1 — an unconditional find makes the `json→pugixml→minio-cpp→sgns-blockstore` superbuild chain a hard prerequisite of *every* build leg including mobile and downstream wallets. OFF-by-default keeps all existing lanes bit-identical at configure time.

### Pattern 2: Trailing-defaulted-struct parameter threading (INTG-02)

**What:** `GlobalDB::New` gains `ColdStorageOptions cold_storage_options = ColdStorageOptions{}` after the existing `BackupOptions backup_options = BackupOptions{ false, 15, 12, true }` (`globaldb.hpp:54-63`), assigned to a member before `Init()` exactly like `globaldb.cpp:86-88`:

```cpp
// Verbatim existing pattern (globaldb.cpp:86-88, read this session):
auto new_instance = std::shared_ptr<GlobalDB>( ... );
new_instance->backup_options_ = backup_options;
```

**Why this shape:** all 8 existing call sites (`GeniusNode.cpp:2119`, `GlobalDbNetworkComposition.cpp:225`, five migration files, plus default-arg callers) compile unchanged — the SC2 byte-identical bar at the source level.

### Pattern 3: Strict tri-state parse inside a lenient legacy loader

**What:** keep `LoadCrdtConfig`'s file-level leniency (D-06); add a nested-object parser with member iteration (unknown-key detection) — the iteration precedent is already in the file's sibling `LoadLogConfig`:

```cpp
// Verbatim existing member-iteration precedent (GeniusNode.cpp:622-627):
for ( auto it = config_json["loggers"].MemberBegin(); it != config_json["loggers"].MemberEnd(); ++it )
{
    if ( !it->value.IsString() )
    {
        node_logger_->warn( "log_config.json: logger '{}' value is not a string, skipping", ... );
```

For `blockstore`, the same loop shape flips from warn-and-skip to collect-and-fail-loud, plus: wrong-typed known field ⇒ loud; missing/blanks ⇒ the D-04 partial-fill rule **after** env resolution (credentials from `SGNS_BLOCKSTORE_S3_*` satisfy the credential requirement — CONTEXT "Derived composition" note, planner should confirm at plan time).

### Pattern 4: Tier-1 label transplant (TEST-01)

**What:** SuperGenius's `addtest()` registers with no labels; the library's convention is one `set_tests_properties` line per registration:

```cmake
# Verbatim precedent (thirdparty/sgns-blockstore/test/CMakeLists.txt:10-17):
addtest(memory_block_store_test memory_block_store_test.cpp)
target_link_libraries(memory_block_store_test
    sgns-blockstore
    p2p::p2p_cid
)
set_tests_properties(memory_block_store_test PROPERTIES LABELS "Tier1")
```

SuperGenius-side: `addtest(cold_storage_config_gate_test ...)` + `set_tests_properties(... LABELS "Tier1")` in `SuperGenius/test/src/crdt/CMakeLists.txt` (crdt_test dir precedent at `:1-36`). The lane: `ctest --test-dir <build> -C <type> -L Tier1 --no-tests=error` — `-L` never includes unlabeled tests (fail-closed), `--no-tests=error` fails an empty selection (a label typo cannot pass vacuously) — `thirdparty/sgns-blockstore/docs/testing-tiers.md` §"The CI lane".

### Anti-Patterns to Avoid

- **Unconditional `find_package(sgns-blockstore REQUIRED)`** — breaks every mobile/default leg (P12 trap 1).
- **Placing the new finds inside the libssh2 `PREFER_CONFIG` window** — re-routes the httplib chain's ZLIB find into `ZLIBConfig.cmake` and corrupts the config check (superbuild's own documented trap, `thirdparty/build/CommonTargets.cmake:897-915`).
- **Setting `CMAKE_FIND_PACKAGE_PREFER_CONFIG ON` around the block** — same trap, inverse direction. Leave global PREFER_CONFIG state alone.
- **Copying `LoadCrdtConfig`'s per-member leniency for the new section** — silent-disable is precisely what INTG-02 forbids (P10).
- **Direct `#include <miniocpp/...>` or httplib usage in SuperGenius source** — breaks SC2 containment; touch only `sgns-blockstore/*` headers.
- **Logging `access_key`/`secret_key` values in the config-loaded info line** — the existing backup-config line (`GeniusNode.cpp:602-609`) prints every field; the new line must print endpoint/bucket only.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| S3 client construction | new client wiring against minio-cpp from SuperGenius | installed `OpenMinioS3Client(S3ClientConfig)` (`S3Client.hpp:197-211`) | factory is the Phase-6 deliverable; eager validation (empty endpoint/bucket ⇒ `std::invalid_argument`) complements loader-time loudness; zero network I/O at construction |
| S3 fake for SuperGenius-side tests | pulling the library's src-only `InMemoryS3Client.hpp` (it is NOT installed — `include/sgns-blockstore/` listing verified) | small in-test fake implementing the **installed** `S3Client` interface (pure virtual, `S3Client.hpp:146-192`), or the installed `MemoryBlockStore` for store-level fakes | the interface is installed precisely so consumers can fake it; the CONTEXT's "InMemoryS3Client fake" is satisfied in spirit by an interface-equivalent fake on the consumer side |
| Unknown-key detection | string-set membership via repeated `HasMember` calls only | one `MemberBegin()/MemberEnd()` pass building a validated field map (LoadLogConfig precedent) | names the offending key in the error (D-05) with one loop, and type-checks each value in the same pass |
| Tier-audit machinery | new audit scripts | copy `thirdparty/sgns-blockstore/test/tier1_audit_check.cmake` pattern (registration-vs-label count guard) | v1.0-proven tripwire against unlabeled registrations |
| Credential redaction | ad-hoc string scrubbing of log lines | never format the keys into any log line; log only endpoint/bucket/prefix/path_style/tls (`S3Client.hpp` field docs already mandate never-log) | redaction-by-omission is the only airtight proof for the log-scan test |

**Key insight:** Phase 7's risk is concentrated in *wiring*, not logic — every mechanism it needs (config-mode finds, trailing defaulted params, member iteration, label properties, env reads) already has an in-repo precedent cited above.

## Runtime State Inventory

> Phase 7 is integration wiring, not a rename/refactor/migration — no stored data, live-service config, OS-registered state, or build-artifact renames are touched. Skipped per protocol.

## Common Pitfalls

### Pitfall 1: httplib's QUIET sub-find fails the whole configure
**What goes wrong:** `find_package(sgns-blockstore)` → its config runs `find_dependency(miniocpp)` → miniocpp's consumer config resolves httplib via a QUIET config find whose target "does not register for find_package's imported-target-reference verification" → `miniocpp_FOUND FALSE` with "imported targets are referenced, but are missing: httplib::httplib".
**Why it happens:** documented Phase-3 spike (2026-10-21); the fix is consumer-side (`thirdparty/sgns-blockstore/CMakeLists.txt:45-56` comment).
**How to avoid:** `find_package(httplib CONFIG REQUIRED)` with an explicit `httplib_DIR` hint BEFORE miniocpp/sgns-blockstore, exactly like the library root and the out-of-tree proof (`test/out_of_tree_consumer/CMakeLists.txt:24-32`).
**Warning signs:** configure error mentioning `httplib::httplib` missing.

### Pitfall 2: ZLIB / PREFER_CONFIG interaction differs from the superbuild context
**What goes wrong:** the superbuild guards its sgns-blockstore sub-build with `-DCMAKE_FIND_PACKAGE_PREFER_CONFIG:BOOL=OFF` + a FindZLIB shim (`CommonTargets.cmake:897-917`), because PREFER_CONFIG ON re-routes the httplib chain's ZLIB find into `ZLIBConfig.cmake` and corrupts the header-path check. The consumer builds are a *different* ZLIB context: SuperGenius already finds ZLIB CONFIG-mode at `build/CommonBuildParameters.cmake:30-31` (`ZLIB_DIR` = thirdparty tree); GeniusSDK sets `ZLIB_DIR` (`:44`) and lets libssh2's `find_dependency(ZLIB)` resolve it *inside* its PREFER_CONFIG window.
**Why it happens:** the trap was characterized in the superbuild context; the consumer context has not yet exercised the httplib chain.
**How to avoid:** keep the block outside the window (PREFER_CONFIG unset ⇒ module/config per call-site defaults); reuse the already-found ZLIB target rather than re-finding. Treat the **first `-DSGNS_COLD_STORAGE=ON` configure on each platform as a verification checkpoint**, not a formality.
**Warning signs:** httplib/miniocpp config errors mentioning zlib prefixes or header-path check failures.

### Pitfall 3: nlohmann_json's install layout
**What goes wrong:** hinting `json/lib/cmake/nlohmann_json` — wrong; upstream installs to the GNUInstallDirs datadir.
**How to avoid:** `"${_THIRDPARTY_BUILD_DIR}/json/share/cmake/nlohmann_json"` — verified in-tree (`SuperGenius/.../CommonBuildParameters.cmake:486`, `GeniusSDK/.../:417`, superbuild note `CommonTargets.cmake:806-808`).

### Pitfall 4: GeniusSDK ordering — the SDK consumes SuperGenius as an exported package
**What goes wrong:** `GeniusSDK/cmake/CommonBuildParameters.cmake:462` runs `find_package(SuperGenius CONFIG REQUIRED)`; `SuperGenius/cmake/config.cmake.in` is bare (just `include(.../supergeniusTargets.cmake)` — read this session). Once any SuperGenius export target references `sgns-blockstore::sgns-blockstore` (PUBLIC link, or PRIVATE-static ⇒ `$<LINK_ONLY:...>`), the SDK configure fails with missing imported target unless sgns-blockstore was found **first**.
**How to avoid:** SDK-side block must precede `:462`. Optionally (Phase-6 D-07 "harden as forced" posture): only add `find_dependency(sgns-blockstore)`-chain entries to `SuperGenius/cmake/config.cmake.in` if the SDK proof forces it. Keep the SDK block self-contained (set its own `nlohmann_json_DIR` even though `:417` sets it later).
**Warning signs:** SDK configure error "imported targets referenced, but are missing: sgns-blockstore::sgns-blockstore".

### Pitfall 5: "Dual RocksDB 9.4/11.1" is dual-COMPAT, not two archives
**What goes wrong:** planning SC1 as "ship two RocksDB versions in one binary" would introduce exactly the MSVC static-link duplicate-symbol/global-state hazard (M1) the research warns about.
**Ground truth (verified this session):** `thirdparty/rocksdb/include/rocksdb/version.h` reads `#define ROCKSDB_MAJOR 9`, `ROCKSDB_MINOR 4`, `ROCKSDB_PATCH 0` — one RocksDB in-tree; the superbuild's sgns-blockstore entry points at the *same* `RocksDB_DIR` (`CommonTargets.cmake:884`). "9.4/11.1" is the library's unversioned-`find_package` dual-compat posture (standalone consumer trees at 11.1.2 verified in v1.0; SameMajorVersion note at `thirdparty/sgns-blockstore/CMakeLists.txt:45-49`).
**How to avoid:** interpret SC1's link proof as (a) NO version argument on any RocksDB find, (b) verifying no second RocksDB archive enters the link (the miniocpp chain pulls none), (c) one binary linking cleanly on Windows/Linux/macOS with the option ON.
**Warning signs:** any `find_package(RocksDB 9...` version pin; linker errors about duplicate `rocksdb::` symbols.

### Pitfall 6: `--no-tests=error` × OFF-by-default = failing lane
**What goes wrong:** if every cold test target is registered only under `SGNS_COLD_STORAGE`, a default (OFF) CI run of `ctest -L Tier1 --no-tests=error` selects ZERO tests and **errors** — the lane fails from day one, or worse, someone "fixes" it by dropping `--no-tests=error` (fail-open).
**How to avoid:** compile `ColdStorageOptions` + strict parsing + env resolution **unconditionally** (they depend only on rapidjson, which `crdt_globaldb` already links PRIVATE) and register the config-gate tests unconditionally; gate only the sgns-blockstore-linking construct code (and its tests) behind the option. Alternative (if planner prefers full gating): run the Tier-1 invocation only in ON lanes — but then the default lane never proves fail-closedness.
**Warning signs:** CI "no tests selected" errors; Tier1 label present on zero targets in default builds.

### Pitfall 7: The wallet Settings screen corrupts a nested blockstore object
**What goes wrong (verified verbatim this session):** `_configFieldsTable` (`GeniusWallet/lib/settings/settings_screen.dart:383-437`) maps over **every** entry of `_crdtConfig`; for non-bool entries it renders `initialValue: entry.value.toString()` and `onChanged: (v) => setState(() => config[entry.key] = v)` — typing one character in a hypothetical blockstore row replaces the nested Map with a String; `_saveCrdtConfig` then writes the whole map to the overrides file (`:154-158`) → at next node start the strict parser sees a malformed section → **loud startup failure caused by a UI edit**.
**How to avoid:** filter the CRDT table to known keys — the Network section already does exactly this: `json.entries.where((e) => whitelist.contains(e.key))` (`:132-135`). Minimal change: `config.entries.where((e) => keyLabels.containsKey(e.key))` in `_configFieldsTable` (or CRDT-section-only filtering).
**Warning signs:** any wallet UI test editing CRDT config after the asset gains the section.

### Pitfall 8: Silent-disable / blank-vs-missing confusion (P10)
**What goes wrong:** copy-pasting the lenient backup-parse shape (`HasMember && Is*` per member, warn-and-continue) into the blockstore parser silently disables cold storage on typos.
**How to avoid:** the locked tri-state matrix (D-03..D-06) + the derived rule that the required-field check runs **after** env resolution; three-case tests (absent/blank/malformed) produce three distinct observable outcomes (P10 checklist).
**Warning signs:** any `using defaults` warn line in a blockstore test's captured output.

### Pitfall 9: "Byte-identical" includes the log stream
**What goes wrong:** adding an info line like "cold storage disabled" when the section is absent changes observable output — SC2's byte-identical bar is proven by a config-gate test that likely asserts on construction/no-new-code-path, but log-noise deltas still violate the spirit and can break log-diff-based tests.
**How to avoid:** when disabled, emit nothing new at info level (a single debug-level line at most); the loaded-configs info line should only appear when the section is present-and-valid (and then prints endpoint/bucket, never keys).
**Warning signs:** any new unconditional log line in the disabled path.

### Pitfall 10: CI's ON-lane depends on the thirdparty release tarball
**What goes wrong:** SuperGenius CI does not build thirdparty — it downloads a released tarball (`SuperGenius/.github/workflows/cmake.yml:318-331`, `gh release download ... --repo GeniusVentures/thirdparty`) and configures with `-DTHIRDPARTY_BUILD_DIR=...`. If the current release predates Phase 6, the tarball has no sgns-blockstore/minio-cpp/pugixml install trees and every ON configure fails at the find.
**How to avoid:** verify the newest thirdparty release tag's tarball contents before wiring the ON lane into CI; if stale, either cut a release first or point the ON lane at a locally-built tree with committed evidence (v1.0 pattern) until the release catches up. (Open Question 1.)
**Warning signs:** CI configure failures mentioning `sgns-blockstore_DIR`/`miniocpp_DIR` not found.

### Pitfall 11: Multi-submodule commit mechanics
**What goes wrong:** GSD commits from the workspace root, but Phase 7 edits live in three submodules + root docs; committing only the root leaves submodule working trees dirty and the next fresh-clone proof (P12) fails on unpushed commits — the exact v1.0 audit tech-debt.
**How to avoid:** each plan's commit step lands inside the touched submodule first, then the root pointer bump; the verify command runs from pushed-commits state wherever feasible.

### Pitfall 12: Existing CI lane is fail-OPEN for unlabeled tests
**What goes wrong:** current CI runs `ctest . -j N -C <type> --output-on-failure -LE requires_foundry` (`cmake.yml:604`, `:674-676`) — `-LE` *excludes labeled* tests and runs everything unlabeled: the opposite selection from `-L Tier1`. Assuming "tests run in CI" covers the fail-closed lane is wrong.
**How to avoid:** the Tier-1 lane is a **separate explicit invocation** (new step/job or documented command); the default lane keeps running everything. Both coexist.

## Code Examples

### 1. GeniusNode-side strict tri-state parse (sketch — exact wording is agent discretion)

```cpp
// Precedents, verbatim mechanics from this session's reads:
//   file-level leniency (D-06)          — GeniusNode.cpp:566-571 warn + return
//   member iteration (D-05 unknown key) — GeniusNode.cpp:622-627 (LoadLogConfig)
//   loud failure                         — GeniusNode.cpp:358-369 constructor throws
//                                           std::runtime_error on init failure
void GeniusNode::LoadCrdtConfig()
{
    crdt_backup_config_ = crdt::GlobalDB::BackupOptions{ true, 15, 12, true };
    // ... existing file-missing / parse-error lenient early returns stay VERBATIM ...

    if ( config_json.HasMember( "blockstore" ) )
    {
        const auto &section = config_json["blockstore"];
        if ( !section.IsObject() )
        {
            throw std::runtime_error( "crdt_config.json: 'blockstore' must be an object" );
        }
        for ( auto it = section.MemberBegin(); it != section.MemberEnd(); ++it )
        {
            if ( kKnownBlockstoreKeys.count( it->name.GetString() ) == 0 )
            {
                throw std::runtime_error( std::string( "crdt_config.json: unknown key 'blockstore." )
                                          + it->name.GetString() + "'" );
            }
            // type-check each known key here; wrong type => loud, naming the key
        }
        // env resolution BEFORE the required-field check (D-07/D-08 + derived rule):
        //   getenv("SGNS_BLOCKSTORE_S3_ACCESS_KEY") overrides access_key, etc.
        // all four required (endpoint,bucket,access_key,secret_key post-env) blank => disabled,
        // any filled while another blank => throw naming the missing field (D-04)
    }
}
```

### 2. GlobalDB threading (diff-shaped)

```cpp
// globaldb.hpp — after BackupOptions (verbatim struct at :28-34 read this session):
struct ColdStorageOptions
{
    bool     enabled{ false };
    std::string endpoint;
    std::string bucket;
    std::string accessKey;   // resolved post-env; NEVER logged
    std::string secretKey;   // resolved post-env; NEVER logged
    std::string prefix;      // maps to S3BlockStoreOptions::keyPrefix ("v1/blocks" default)
    bool     pathStyle{ true };
    bool     tls{ false };
};
// New() gains, after the BackupOptions param (:63):
//     ColdStorageOptions cold_storage_options = ColdStorageOptions{}
// globaldb.cpp New() body gains, beside backup_options_ (:86-88):
//     new_instance->cold_storage_options_ = cold_storage_options;
```

### 3. Tier-1 registration in SuperGenius

```cmake
# SuperGenius/test/src/crdt/CMakeLists.txt (crdt_test precedent :1-36; addtest from
# SuperGenius/cmake/functions.cmake:8-38 — no LABELS support today, so the
# set_tests_properties line is mandatory, not optional):
addtest(cold_storage_config_gate_test cold_storage_config_gate_test.cpp)
target_link_libraries(cold_storage_config_gate_test
    crdt_globaldb     # rapidjson arrives PRIVATE through this target
)
set_tests_properties(cold_storage_config_gate_test PROPERTIES LABELS "Tier1")
```

### 4. Wallet whitelist filter (one-line shape)

```dart
// settings_screen.dart — Network section precedent (:132-135):
//   json.entries.where((e) => whitelist.contains(e.key))
// CRDT fix: render only known flat keys so a nested 'blockstore' object
// round-trips untouched through load -> edit -> save:
config.entries.where((e) => keyLabels.containsKey(e.key))
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| v1.0 planning assumption: package config does only `find_dependency(RocksDB)`; consumer must hand-find libp2p + miniocpp chain | Phase-6 hardened config does `find_dependency` for RocksDB, libp2p, ipfs-lite-cpp, miniocpp | Phase 6 (2026-10) | Phase 7's block is smaller; only httplib/pugixml/nlohmann_json hints + explicit httplib find remain mandatory |
| `InMemoryS3Client` unreachable out-of-tree (src-only) | Installed `OpenMinioS3Client` factory with eager validation, zero network I/O at construction | Phase 6 (LIB-02/D-05/D-06) | Config-gate "valid config constructs" case is hermetic with the REAL client; no fake needed for Phase 7's tests |
| sha-256-only CID gate | {sha-256, blake2b-256} accepted | Phase 6 (LIB-01) | CRDT DAG CIDs flow through library gates unchanged — no Phase 7 action, but the widening is why Phases 8+ can spill |

**Deprecated/outdated:** none newly; do not adopt the older STACK-research config sketch (it sketched `port`/`region`/`use_tls`/`tls_verify`/`local_cache_dir`/`drain_interval_seconds`/`retention_hours`) — CONTEXT D-02 locked the smaller field set (`endpoint`, `bucket`, `access_key`, `secret_key`; optional `prefix`, `path_style`, `tls`). Note `S3ClientConfig` itself still carries port/region/tlsVerify fields with defaults (`S3Client.hpp:58-72`, verbatim below) — `ColdStorageOptions` maps the locked subset onto it and lets the rest default (agent discretion item).

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | The interpreted dual-RocksDB proof (single 9.4 shared; no version pins; no second archive; 3-platform link) satisfies SC1's wording — not literally shipping 9.4+11.1 in one binary | Pitfall 5 | Planner may schedule impossible/pointless work; verifier may reject a correct proof — flag at plan time for user confirmation |
| A2 | Linux/macOS legs for the ON-build link proof are reachable via existing self-hosted CI runners (matrix at `cmake.yml:158-167`); Windows provable locally | Environment Availability | If unavailable, three-platform proof needs committed dev-machine evidence instead (v1.0 pattern) |
| A3 | The newest thirdparty release tarball contains the Phase-6 install trees (sgns-blockstore/minio-cpp/pugixml/json) — NOT verified this session | Pitfall 10, Open Q1 | CI ON-lane fails at configure; needs release cut or local-tree evidence path |
| A4 | Compiling `ColdStorageOptions`+parse+env code unconditionally (only library-linking code gated) is acceptable within "OFF by default" — the option gates linkage/construction, not type definitions | Pattern 1/2, Pitfall 6 | If user reads SC1 as full conditional compilation, the always-green Tier-1 lane needs the ON-lane-only alternative |
| A5 | Required-field check runs after env resolution (CONTEXT's own "Derived composition" note — follows from D-07/D-08 but not independently user-confirmed) | Pattern 3 | If wrong, env-credential feature is unusable without file secrets; planner should confirm at plan time as CONTEXT instructs |
| A6 | `ctest -L Tier1` at the SuperGenius build root discovers only labeled tests across all subdirectories (test/, SGProcessingManager, ProofSystem) — standard ctest behavior, not exercised on this tree this session | Pattern 4 | If subdirectory registration quirks exist, lane invocation may need `--test-dir` pointing at the registering subdirectory |
| A7 | The config-gate test asserting "no blockstore constructed, byte-identical" is practical as a unit-level test on `LoadCrdtConfig`/`GlobalDB::New` (parse result + no-construct), not a full-node golden-log diff | INTG-02 SC2 | Full-node byte-identical proof is much heavier; planner should scope the test to the seam |

## Open Questions

1. **Thirdparty release tarball currency (A3)**
   - What we know: CI downloads released thirdparty tarballs (`cmake.yml:318-331`); install trees exist locally (superbuild-built).
   - What's unclear: whether the newest published release includes Phase-6 trees.
   - Recommendation: check the newest `GeniusVentures/thirdparty` release contents as Wave-1 task zero; if stale, run the ON-lane proof against a local superbuild tree with committed evidence and file the release cut as a follow-up.
2. **Where the Tier-1 invocation lives (SC4 "CI lane in place")**
   - What we know: existing CI runs the fail-open `-LE requires_foundry` full suite; the library's lane is a workflow step.
   - What's unclear: new step in `cmake.yml` vs new job vs documented command executed by verify.
   - Recommendation: a dedicated lightweight step/job running `ctest -L Tier1 --no-tests=error` after the existing test step — cheapest way to make "fail-closed in CI" literally true.
3. **Loud-failure surface (agent discretion)**
   - `throw std::runtime_error` from the `GeniusNode` init path (constructor already throws — `GeniusNode.cpp:358-369`) vs propagating an `outcome::failure` from `GlobalDB::New` (which `InitDatabase` already logs-and-breaks on, `GeniusNode.cpp:2129-2133`).
   - Recommendation: throw from `LoadCrdtConfig`'s caller path — config errors are config-load errors; they should fail before any GlobalDB/ RocksDB work, and the message reaches the operator with the field name.
4. **Wallet asset shape (agent discretion)** — omit the section (invisible; zero UI exposure) vs ship `"blockstore": {}` (documents the capability in-asset; D-03-equivalent). With the Pitfall 7 filter in place either is safe; omitting is marginally safer for older wallet builds whose Settings screen lacks the filter.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| thirdparty superbuild install trees (sgns-blockstore, minio-cpp/httplib, pugixml, json) — Windows/Debug | INTG-01 local proof | ✓ (paths Test-Path'd this session under `thirdparty/build/Windows/Debug/`) | Phase-6 state | rebuild superbuild target `sgns-blockstore` (proven Phase-6 command in workstream STATE/plans) |
| SuperGenius build tree (`SuperGenius/build/Windows/Debug`) | config-gate tests, ON-configure proof | ✓ (`CMakeCache.txt` present) | current | fresh configure per TESTING.md |
| GeniusSDK build tree (`GeniusSDK/build/Windows/Debug`) | SDK-side configure proof | ✓ (`CMakeCache.txt` present) | current | fresh configure |
| CMake + VS 2022 toolchain | all builds | ✓ (existing build trees prove it) | ≥3.22 | — |
| Linux + macOS legs | SC1 three-platform link proof | ✗ locally (Windows dev box) | — | self-hosted CI matrix (`cmake.yml:158-167`) or committed dev-machine evidence (A2) |
| ctest label support | Tier-1 lane | ✓ (CTest core feature; already used by thirdparty lane) | — | — |

**Missing dependencies with no fallback:** none blocking local development; the three-platform SC1 proof requires CI or another machine (A2).

**Missing dependencies with fallback:** thirdparty release tarball currency (A3) — local superbuild tree substitutes for lane proof.

## Security Domain

`security_enforcement: true`, ASVS Level 1, block-on-high (`.planning/config.json`). This phase's security surface is config/secret handling, not new crypto.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | S3 credentials are static keys, not user auth — handled as secrets below |
| V3 Session Management | no | no sessions introduced |
| V4 Access Control | no | no new authority surface; consensus untouched |
| V5 Input Validation | **yes** | strict tri-state schema validation of the `blockstore` section (D-03..D-06) IS input validation — rapidjson type checks + unknown-key rejection + loud failure naming the offending field; `OpenMinioS3Client` adds eager endpoint/bucket validation as the second layer |
| V6 Cryptography | no | no new cryptographic primitives; credential *transport* only |
| V7 Error Handling / V14 Logging | **yes** | malformed-config errors must be loud AND non-leaking; the loaded-config log line prints endpoint/bucket/prefix only — keys never formatted into any log line (library field docs already mandate this, `S3Client.hpp:68-69` region) |
| V8 Data Protection | **yes** (secrets at rest) | credentials supplied via env vars (`SGNS_BLOCKSTORE_S3_*`) never need to exist in `crdt_config.json`; when file values are used, they mirror into GlobalDB backups/node images (P10) — env path is the documented secure default; docs (D-10 runbook) should say so |

### Known Threat Patterns for this integration

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Secrets disclosure via logs (keys printed on config load / error paths) | Information Disclosure | redaction-by-omission (never format keys); log-scan test asserts captured output of every config-load path contains no credential substring (SC3 evidence) |
| Secrets at rest in config file / its backups | Information Disclosure | env-var override precedence (D-07); wallet asset ships blank; runbook documents env-only for servers |
| Silent misconfiguration (operator believes cold storage is on) | Tampering/Elevation | loud startup failure on partial/malformed/unknown-key sections (D-04/D-05); never silent-disable |
| Config injection via env stray (env activates feature unintentionally) | Tampering | env never activates (D-08) — test case: env set + blank config ⇒ still disabled |
| Malicious/typo'd field names surviving to runtime | Tampering | unknown-key loud failure at startup (D-05) |
| Credential leakage through `S3ClientConfig` copies in error messages | Information Disclosure | failure paths log `BlockStatus` only (library contract); SuperGenius error strings interpolate field NAMES, never values |

## Sources

### Primary (HIGH confidence — read in-tree this session)
- `SuperGenius/build/CommonBuildParameters.cmake` — ZLIB CONFIG find `:30-31`; RocksDB `:119-120`; libssh2 PREFER_CONFIG window `:392-405`; AsyncIOManager `:408-409`; nlohmann_json `:486-487`; `BUILD_TESTING` cache `:13`, GTest `:33-37`; `enable_testing()`/`add_subdirectory` structure `:554-586`; `install(EXPORT supergeniusTargets)` `:579-586`
- `GeniusSDK/cmake/CommonBuildParameters.cmake` — ZLIB_DIR `:44`; RocksDB `:142-144`; libssh2 window `:291-311`; AsyncIOManager `:313-317`; gnus_upnp `:320-323`; nlohmann_json `:417-418`; `find_package(SuperGenius CONFIG REQUIRED)` `:462`
- `SuperGenius/build/Windows/CMakeLists.txt` — 63-line platform entry; MSVC runtime `/MT` discipline
- `SuperGenius/build/CommonCompilerOptions.cmake` — `THIRDPARTY_BUILD_DIR` resolution + `_THIRDPARTY_BUILD_DIR` alias `:219-282`
- `SuperGenius/cmake/functions.cmake` — `addtest()` `:8-38` (no LABELS), `addtest_part()` `:40+`
- `SuperGenius/cmake/config.cmake.in` — bare targets-include only
- `SuperGenius/src/account/GeniusNode.cpp` — constructor throws `:358-376`; `LoadCrdtConfig()` `:552-610` (defaults `:554`, file-missing `:557-563`, parse-error `:566-571`, backup members `:575-591`, zero-clamps `:594-601`, info log `:602-609`); `LoadLogConfig` member-iteration `:612-627`; `InitDatabase`/`GlobalDB::New` call `:2117-2133`
- `SuperGenius/src/account/GeniusNode.hpp` — `write_base_path_` `:1000`; `LoadCrdtConfig` `:1383`; `crdt_backup_config_` `:1624`
- `SuperGenius/src/crdt/globaldb/globaldb.hpp` — `BackupOptions` `:28-34`; `New` signature with defaulted `BackupOptions` `:54-63`; `backup_options_` member `:330`
- `SuperGenius/src/crdt/globaldb/globaldb.cpp` — `New` `:67-92` (member assignment `:86-88`); IpfsDatastore seam (`IpfsRocksDb::create` → `RocksdbDatastore` → `GraphsyncDAGSyncer` → `CrdtDatastore::New`) ~`:322-365`; backup loop `:429-477`; restore/abort precedent `:250-282`
- `SuperGenius/src/crdt/CMakeLists.txt` + `globaldb/CMakeLists.txt` — `crdt_globaldb` target (rapidjson PRIVATE) + `supergenius_install` pattern
- `SuperGenius/test/CMakeLists.txt`, `test/src/CMakeLists.txt`, `test/src/crdt/CMakeLists.txt` — test tree layout + `addtest(crdt_test ...)` shape
- `thirdparty/sgns-blockstore/CMakeLists.txt` — dual-compat note `:45-49`; httplib-first ordering `:50-63`; TESTING gate `:65-71`; install/export/version `:73-113`
- `thirdparty/sgns-blockstore/src/CMakeLists.txt` — `PUBLIC p2p::p2p_cid / PUBLIC RocksDB::rocksdb / PRIVATE miniocpp::miniocpp / PRIVATE ipfs-lite-cpp::blake2` `:20-27` (read this session)
- `thirdparty/sgns-blockstore/cmake/config.cmake.in` — Phase-6 hardened `find_dependency` set (RocksDB, libp2p, ipfs-lite-cpp, miniocpp)
- `thirdparty/sgns-blockstore/include/sgns-blockstore/S3Client.hpp` — `S3ClientConfig` fields verbatim (`endpoint; port=0; region="us-east-1"; useTls=false; tlsVerify=true; pathStyle=true; accessKey; secretKey; bucket`, `:58-72`); `S3Client` interface `:146-192`; `OpenMinioS3Client` + eager-validation/zero-I/O contract `:197-211`
- `thirdparty/sgns-blockstore/include/sgns-blockstore/` listing — `InMemoryS3Client.hpp` NOT installed (14 installed headers enumerated)
- `thirdparty/sgns-blockstore/S3BlockStore.hpp` / `LocalBlockStore.hpp` — `S3BlockStoreOptions::keyPrefix = "v1/blocks"`; `LocalBlockStoreOptions::path`; `Open()` factories
- `thirdparty/sgns-blockstore/test/out_of_tree_consumer/{CMakeLists.txt,run_consumer_proof.cmake}` — consumer find shape + full hint-closure list (`:59-105`)
- `thirdparty/sgns-blockstore/test/CMakeLists.txt` — LABELS convention `:10-17` et seq.; src/-include test-surface privilege pattern
- `thirdparty/sgns-blockstore/docs/testing-tiers.md` — tier table, `-L Tier1 --no-tests=error` fail-closed rationale, no-skip-meta-test decision
- `thirdparty/build/CommonTargets.cmake` — rocksdb entry `:140-173` (static, snappy, superbuild flags); ZLIB/PREFER_CONFIG trap note `:897-917`; sgns-blockstore entry (hint closure, PREFER_CONFIG OFF last-arg rule, `TESTING` re-enable) `:826-922`
- `thirdparty/rocksdb/include/rocksdb/version.h` — `ROCKSDB_MAJOR 9 / MINOR 4 / PATCH 0` (verbatim)
- `GeniusWallet/assets/crdt_config.json` — verbatim 4-key content
- `GeniusWallet/lib/settings/settings_screen.dart` — `_readSdkJson` `:74-88`; `_writeOverrides` `:90-100`; network whitelist filter `:130-135`; `_loadCrdtConfig`/`_saveCrdtConfig` `:148-160`; `_configFieldsTable` `:383-437` (renders every entry; string write-back)
- `SuperGenius/.github/workflows/cmake.yml` + `build-release-tags.yml` — tarball download `:318-331`; configure line `:523`; full-suite ctest `-LE requires_foundry` `:604/:674-676`; self-hosted matrix `:158-167`
- Root `.gitmodules` + `thirdparty/.gitmodules` — submodule topology (SuperGenius/GeniusWallet/GeniusSDK/thirdparty at root; sgns-blockstore nested in thirdparty)
- `.planning/workstreams/rocksdb-backup/phases/07-.../07-CONTEXT.md` — decisions D-01..D-10 (verbatim constraints above)
- `.planning/workstreams/rocksdb-backup/REQUIREMENTS.md` — INTG-01/INTG-02/TEST-01 letters + Out of Scope table
- `.planning/research/STACK-rocksdb-backup-2026-10-22.md` — pre-Phase-6 consumption analysis (superseded in part by Phase-6 config hardening; cross-checked this session)
- `.planning/research/PITFALLS-rocksdb-backup-2026-10-22.md` — P10 (config traps), P12 (build/CI traps, incl. dual-RocksDB note), M1, M3 (closed by D-09/D-10)

### Secondary (MEDIUM confidence)
- `.planning/research/SUMMARY-rocksdb-backup-2026-10-22.md` — phase mapping (via CONTEXT citation; not re-read this session)

### Tertiary (LOW confidence)
- None — no training-data-only claims load-bearing in this document

## Metadata

**Confidence breakdown:**
- Build wiring (INTG-01): HIGH — every placement, hint, and ordering constraint verified against current files this session; Phase-6 artifacts (hardened config, consumer proof) read directly
- Config gate (INTG-02): HIGH — loader, threading seam, wallet asset, and wallet UI all read verbatim; the only soft spots are the flagged discretion choices (A5, loud-failure surface)
- Tier-1 lane (TEST-01): HIGH on mechanics (addtest/LABELS/ctest semantics documented in-repo and re-read), MEDIUM on CI integration specifics (A2/A3/A6 — runner and tarball currency unverified)
- Dual-RocksDB reinterpretation (A1): HIGH on the ground truth (version.h, single shared tree), MEDIUM on whether it matches SC1's intent — planner must confirm

**Research date:** 2026-10-23
**Valid until:** 2026-11-23 (stable internal codebase; re-check if thirdparty release or Phase-8 work lands first)
