# Stack Research

**Domain:** SuperGenius cold-storage integration — consuming the shipped `sgns-blockstore` static library from the SuperGenius node (rocksdb-backup workstream, v1.1)
**Researched:** 2026-10-22
**Confidence:** HIGH (build mechanism, exported-target names, install-tree layout, config seam — all verified against the tree with file:line cites); MEDIUM on mobile-superbuild leg coverage (unverified, flagged below)

**Scope guard:** v1.0 of `thirdparty/sgns-blockstore` is shipped and verified — this file covers ONLY what v1.1 adds on the consumer side: (1) build wiring + config, (2) spill-on-write, (3) cold read fallback, (4) GC. No new external dependencies are recommended anywhere below.

---

## Critical Constraints Found (read first — they shape phase 1)

Two facts about the library *as shipped* mean v1.1 cannot be pure consumer-side work. Both fixes are **additive changes inside `thirdparty/sgns-blockstore` (our own repo)** — not new external deps — but the planner must schedule them before/with the SuperGenius wiring.

### Constraint A — CID hash boundary: CRDT blocks are blake2b-256, the library accepts sha-256 only

- Every CRDT block written through the hot path gets its CID from `sgns::common::getCidOf`, which hashes **blake2b-256 + DAG_CBOR** (`thirdparty/ipfs-lite-cpp/primitives/cid/cid.cpp:129-134`).
- sgns-blockstore v1 **rejects any multihash that is not sha-256 at API entry** (programmer-error throw, D-08) — `thirdparty/sgns-blockstore/include/sgns-blockstore/Cid.hpp:66-79` and the same boundary restated in `BlockStore.hpp:46-56`. The headers explicitly name the CRDT CBOR path as the excluded case and state *"widening to more hash functions later is additive."*
- Consequence: "every CRDT block Put spills to cold storage" and "cold read fallback by CID" cannot both work in v1.1 without one of:
  1. **(Recommended) Additive widening of sgns-blockstore to accept blake2b-256** — the stored CID remains the CRDT/graphsync CID end-to-end; cold lookup needs no mapping table. Additive because D-08's rejection set shrinking breaks no correct consumer.
  2. Dual-CID scheme (store under sha-256 via `CidOf`, keep a blake2b→sha-256 mapping) — extra metadata, violates "the CID is authoritative" (`S3BlockStore.hpp:19-23`), complicates GC. Not recommended.
- **Recommendation:** phase 1 of v1.1 should include the blake2b-256 widening inside sgns-blockstore (contract tests extend the conformance kit), keeping the frozen v1 API surface unchanged. Flag for `gsd-planner`: this is a prerequisite for both spill (milestone item 2) and fallback (item 3).

### Constraint B — the production S3 client impl header is not installed

- `MinioS3Client.hpp` lives in `thirdparty/sgns-blockstore/src/` (`thirdparty/sgns-blockstore/src/MinioS3Client.hpp:1-16` — "impl header stays internal") and the install rule only installs `include/` (`thirdparty/sgns-blockstore/CMakeLists.txt:57-60`). Its symbols ARE in the static lib, but a consumer cannot name the type.
- Therefore SuperGenius **cannot construct the production minio-cpp-backed client today**. The installed surface is only the SDK-free `S3Client.hpp` interface (`S3Client.hpp:6-13`).
- **Recommendation:** smallest additive fix consistent with SC2 containment — add an installed factory declaration, e.g. `result<std::shared_ptr<S3Client>, BlockStatus> OpenMinioS3Client(const S3ClientConfig&)` declared in the installed `S3Client.hpp`, defined in the lib next to `MinioS3Client.cpp`. This keeps zero minio-cpp types in installed headers (the impl stays pimpl'd, `MinioS3Client.hpp:8-12`) while giving consumers the production client. Alternative (install `MinioS3Client.hpp` itself) also works but exports an impl header the repo deliberately kept internal.
- Same check applied to the hermetic fake: `InMemoryS3Client.hpp` is also src/-only. **No change needed** — SuperGenius-side tests can fake the cold tier with the installed `MemoryBlockStore.hpp` (a full `BlockStore`), which is the right seam for wrapper tests anyway.

### Constraint C — consumer-side CMake must pre-load the miniocpp chain (static-link transitivity)

- sgns-blockstore links `PUBLIC p2p::p2p_cid`, `PUBLIC RocksDB::rocksdb`, `PRIVATE miniocpp::miniocpp` (`thirdparty/sgns-blockstore/src/CMakeLists.txt:20-27`). PRIVATE deps of a **static** library ride the export as `$<LINK_ONLY:miniocpp::miniocpp>`, so the consumer's configure **fails with "imported targets referenced, but are missing"** unless `miniocpp::miniocpp` already exists — the exact failure mode the repo already hit and documented for httplib (`thirdparty/sgns-blockstore/CMakeLists.txt:23-33`).
- The installed package config only does `find_dependency(RocksDB CONFIG)` (`thirdparty/sgns-blockstore/cmake/config.cmake.in`) — it does **not** pull libp2p or miniocpp. So the consumer must find, in order: libp2p → RocksDB → (pugixml, nlohmann_json, httplib) → miniocpp → sgns-blockstore. Exact wiring in *Installation* below.
- Optionally (nice-to-have, additive): add `find_dependency(libp2p)`/`find_dependency(miniocpp)` to `config.cmake.in` with the same pre-set `*_DIR` hints so future consumers can't hit Constraint C. Recommend doing this in the same v1.1 library touch as Constraint B.

---

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| `sgns-blockstore::sgns-blockstore` (imported target) | 1.0.0 (config version `AnyNewerVersion`) | Cold-storage tiers behind the frozen BlockStore contract | It IS the v1.0 deliverable; exported with namespaced `sgns-blockstore::` namespace (`thirdparty/sgns-blockstore/CMakeLists.txt:64-70`), deliberately better than the un-namespaced `AsyncIOManager` precedent. Link this exact target name. |
| CMake `find_package(... CONFIG REQUIRED)` against the thirdparty install tree | CMake ≥ 3.20 (library) / ≥ 3.22 (platform entry files) | Resolve the superbuild-produced static lib | This is how every existing dep is consumed — rocksdb at `SuperGenius/build/CommonBuildParameters.cmake:119-121`, libp2p at `:240`, ipfs-lite-cpp at `:347`. No new mechanism invented. |
| `crdt_config.json` → new `blockstore` section | — (rapidjson, existing pattern) | Construction config for the cold tiers | Matches `GeniusNode::LoadCrdtConfig` (`SuperGenius/src/account/GeniusNode.cpp:552-610`): file-missing and invalid-file both fall back to defaults — extend the same semantics so a missing/absent section = cold storage disabled = today's behavior exactly. |
| Env-var credential overrides (`SGNS_BLOCKSTORE_S3_*`) | — | Secret delivery without forcing secrets into config files | Honors the architecture doc's principle ("Credentials should come from environment variables, protected secret files, or an external secret manager rather than the main configuration file" — `supergenius-sharded-ipld-cache-architecture.md:539`) while keeping the user's config-field intent. See *Credential delivery* under Installation. |

### Supporting Libraries (all already present — nothing new to add)

| Library | Already in SuperGenius build? | Consumer-side requirement for v1.1 |
|---------|------------------------------|-------------------------------------|
| libp2p (`p2p::p2p_cid` + vendored outcome) | Yes — `SuperGenius/build/CommonBuildParameters.cmake:240-242` | Must be found **before** `find_package(sgns-blockstore)` (export references `p2p::p2p_cid`). No change, just ordering. |
| RocksDB | Yes — `SuperGenius/build/CommonBuildParameters.cmake:119-121` | Library config re-runs `find_dependency(RocksDB CONFIG)`; dual-compat 9.4/11.1 handled by NO version argument on the library side (`thirdparty/sgns-blockstore/CMakeLists.txt:13-17`). No change. |
| miniocpp (+ pinned cpp-httplib v0.53.1, inih r58, pugixml v1.16, nlohmann_json) | **No — new consumer-side entries required** | Constraint C: the consumer must set 4 config-dir vars and `find_package(miniocpp CONFIG REQUIRED)` before sgns-blockstore. Paths verified against the superbuild's observed install layout (see Installation). |
| rapidjson | Yes (used by `LoadCrdtConfig`) | Parse the new section; no change. |
| Boost 1.85 / OpenSSL / zlib | Yes | Already found; the miniocpp chain reuses them. No change. |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| `ctest -L Tier1 --no-tests=error` | Hermetic CI lane for the library | Already wired in `thirdparty/.github/workflows/build.yml` (Windows/Linux/OSX legs; `thirdparty/sgns-blockstore/docs/testing-tiers.md:49-58`). SuperGenius CI does **not** re-run these; it runs its own new integration tests against `MemoryBlockStore`. |
| `MemoryBlockStore` (installed header) | Cold-tier fake for SuperGenius-side wrapper tests | Full `BlockStore` implementation, deterministic, no env gates — the correct test seam for the read-fallback wrapper. Do not reach for the src/-only `InMemoryS3Client`. |
| Tier-3 s3d lane env gates (`SGNS_BLOCKSTORE_TEST_S3D_*`) | Dev-only live verification pattern | If v1.1 wants a live node-level s3d E2E, mirror this gate pattern (`testing-tiers.md` tier table) — loud-labelled skip, never in CI. |

---

## Installation

### 1. Consumer CMake wiring — `SuperGenius/build/CommonBuildParameters.cmake`

Add one block, placed **after** the libp2p find (`:240-242`) and RocksDB find (`:119-121`) (both are prerequisites of the sgns-blockstore export) and **outside** the temporary `CMAKE_FIND_PACKAGE_PREFER_CONFIG ON` window the libssh2 entry toggles (the httplib chain must not be re-routed through `ZLIBConfig.cmake` — same trap the superbuild dodges at `thirdparty/build/CommonTargets.cmake:897-915`):

```cmake
# sgns-blockstore (cold-storage tier) + its transitive static deps.
# Order matters: p2p::p2p_cid / RocksDB::rocksdb are referenced by the
# sgns-blockstore export; miniocpp::miniocpp rides $<LINK_ONLY:...> from the
# PRIVATE static link and must exist at configure time, and miniocpp's
# consumer config re-runs miniocpp-deps.cmake in THIS context (pugixml /
# nlohmann_json / httplib must resolve here too — see
# thirdparty/build/CommonTargets.cmake:874-881 comment).
set(pugixml_DIR          "${_THIRDPARTY_BUILD_DIR}/pugixml/lib/cmake/pugixml")
set(nlohmann_json_DIR    "${_THIRDPARTY_BUILD_DIR}/json/share/cmake/nlohmann_json")  # GNUInstallDirs datadir, NOT lib/cmake
set(httplib_DIR           "${_THIRDPARTY_BUILD_DIR}/minio-cpp/lib/cmake/httplib")
set(miniocpp_DIR          "${_THIRDPARTY_BUILD_DIR}/minio-cpp/lib/cmake/miniocpp")
find_package(miniocpp CONFIG REQUIRED)

set(sgns-blockstore_DIR   "${_THIRDPARTY_BUILD_DIR}/sgns-blockstore/lib/cmake/sgns-blockstore")
find_package(sgns-blockstore CONFIG REQUIRED)
```

Every path above is the consumer-side mirror of the superbuild's own config dirs, verified at `thirdparty/build/CommonTargets.cmake:860` (miniocpp), `:919` (sgns-blockstore), `:806-808` (nlohmann_json datadir note), `:817` (pugixml), and the `-Dhttplib_DIR` line in the sgns-blockstore entry (`:877`). `_THIRDPARTY_BUILD_DIR` is already resolved per-platform with a Release fallback and tarball download (`SuperGenius/build/CommonCompilerOptions.cmake:219-282`), so Debug/Release and prebuilt-tarball workflows all work unchanged.

### 2. Same block in `GeniusSDK/cmake/CommonBuildParameters.cmake`

GeniusSDK statically links the SuperGenius node lib, so its final executables must also resolve the same imported targets at configure time. `GeniusSDK/build/CommonBuildParameters.cmake:1-5` just `include(../../cmake/CommonBuildParameters.cmake)` — the edit belongs in `GeniusSDK/cmake/CommonBuildParameters.cmake`, with `THIRDPARTY_BUILD_DIR` (no underscore — that variant's naming, e.g. rocksdb at `GeniusSDK/cmake/CommonBuildParameters.cmake:110-113`), placed after its libp2p/RocksDB finds. This mirrors how the sgproc-render worktree propagated `vk-bootstrap::vk-bootstrap` to both consumers (PROJECT.md validated requirements: "GeniusSDK/GeniusWallet resolve vk-bootstrap transitively via mirrored find_package").

### 3. Link the target where the wrapper lives

The wrapper library (the `BlockStoreBackedIpfsDatastore`-shaped `IpfsDatastore` decorator + spill/drain orchestration) should be a new target under `SuperGenius/src/crdt/` following the `crdt_*` target pattern (`SuperGenius/src/crdt/CMakeLists.txt` — per-module `add_library` + `target_link_libraries` + `supergenius_install`):

```cmake
target_link_libraries(<new-cold-store-target>
    PUBLIC
    sgns-blockstore::sgns-blockstore   # namespaced export (CMakeLists.txt:64-70)
    ...existing ipfs-lite-cpp::/crdt deps as needed...
)
```

Link it into `crdt_datastore`/`globaldb` (and transitively `genius_node`) per the existing dependency graph. The `$<LINK_ONLY:miniocpp::miniocpp>` on the sgns-blockstore target propagates the SDK symbols to every final link automatically — SuperGenius code never links miniocpp directly (SC2 containment, `thirdparty/sgns-blockstore/src/CMakeLists.txt:22-27`).

### 4. Runtime integration points (for the planner's file map)

| Integration point | File | Mechanism |
|---|---|---|
| Config parsing | `SuperGenius/src/account/GeniusNode.cpp:552-610` (`LoadCrdtConfig`) | New `blockstore` sub-object; missing/invalid → disabled (existing early-return pattern at `:557-563`, `:566-571`) |
| GlobalDB datastore seam | `SuperGenius/src/crdt/globaldb/globaldb.cpp:322-344` | Today: `IpfsRocksDb::create` → `RocksdbDatastore` → `GraphsyncDAGSyncer` + `CrdtDatastore::New`. v1.1: wrap the `RocksdbDatastore` in the cold-fallback decorator (this is the exact seam v1.0's REQUIREMENTS named: "SuperGenius-side BlockStoreBackedIpfsDatastore adapter + globaldb.cpp:322-344 wiring + CommonBuildParameters.cmake consumer entry — later milestone", `.planning/workstreams/rocksdb-backup/milestones/v1.0-REQUIREMENTS.md:68`) |
| The interface to implement | `thirdparty/ipfs-lite-cpp/ipfs_lite/ipfs/datastore.hpp:15+` (`sgns::ipfs_lite::ipfs::IpfsDatastore`) | `set()` = hot write + spill (`LocalBlockStore::Put` journals atomically); `get()` = hot → cold fallback with CID re-verification; `contains()`/`seal()`/`is_sealed()`/`remove()` pass through to hot only — `remove` must NEVER touch cold (eviction ≠ CRDT deletion) |
| Spill drain loop | new, inside the wrapper/orchestrator | `DrainPendingUploads(LocalBlockStore&, BlockStore&, WriteOptions)` (`UploadDrainer.hpp:96-104`) — synchronous one-shot; v1.1 wraps it on a periodic/triggered cadence from config. Both stores are single-threaded-contract (CORE-03), so the drain must not race blockstore calls — serialize through the wrapper's strand/strand-like discipline |
| Wallet asset parity | `GeniusWallet/assets/crdt_config.json` | Currently 4 backup fields; v1.1 adds the same `blockstore` section so node+wallet ship one schema (desktop wallets can leave it blank/disabled) |

### 5. Config schema + credential delivery (recommendation)

```json
{
  "backup_enabled": true,
  "backup_interval_minutes": 15,
  "backup_keep_count": 12,
  "backup_auto_restore_on_repair_failure": true,
  "blockstore": {
    "endpoint": "",          // blank or section absent => cold storage DISABLED (today's behavior)
    "port": 0,
    "region": "us-east-1",
    "bucket": "",
    "use_tls": false,        // s3d on loopback: HTTP is the tested lane; remote deployments set true
    "tls_verify": true,      // S3ClientConfig default; NEVER default off (T-3-02)
    "path_style": true,
    "key_prefix": "v1/blocks",
    "local_cache_dir": "",   // LocalBlockStore's OWN RocksDB dir (never the GlobalDB dir — D-01)
    "access_key": "",
    "secret_key": "",
    "drain_interval_seconds": 30,
    "retention_hours": 0     // GC (milestone item 4); 0 = no GC yet
  }
}
```

Fields map 1:1 onto `S3ClientConfig` (`S3Client.hpp:58-72`), `S3BlockStoreOptions.keyPrefix` (`S3BlockStore.hpp:37-52`), and `LocalBlockStoreOptions.path` (`LocalBlockStore.hpp:85-97`).

**Credential resolution (recommended, in precedence order):**

1. `SGNS_BLOCKSTORE_S3_ACCESS_KEY` / `SGNS_BLOCKSTORE_S3_SECRET_KEY` (and optionally `_ENDPOINT`/`_BUCKET`) env vars — **override** config when set. Naming follows the library's established `SGNS_BLOCKSTORE_` prefix (test gates already use `SGNS_BLOCKSTORE_TEST_S3D_*`, `testing-tiers.md` tier table).
2. `crdt_config.json` `blockstore.access_key` / `secret_key` — supported, per user intent.
3. Either source blank + `endpoint` blank/absent → disabled.

**Rationale (why config fields + env override, not env-only):** the architecture doc's concern is secrets living in "the main configuration file" (`supergenius-sharded-ipld-cache-architecture.md:539`). `crdt_config.json` is the CRDT-scoped file, distributed as a wallet asset (`GeniusWallet/assets/crdt_config.json`) to end-user desktops where requiring env vars would make the feature unusable; s3d in the primary deployment is loopback with per-node credentials. The env override gives operators/CI a config-file-free path and satisfies the doc's principle for server deployments at near-zero cost. Non-negotiables either way: credentials are **never logged** (the `S3ClientConfig` field docs already mandate this, `S3Client.hpp:68-69`), and `LoadCrdtConfig`'s existing info-log line must print endpoint/bucket but redact keys.

---

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| `find_package(sgns-blockstore CONFIG REQUIRED)` against install tree | `add_subdirectory(thirdparty/sgns-blockstore)` into the SuperGenius build | Never for v1.1 — recompiles the lib per consumer, drags its whole dep closure (miniocpp clone-on-demand at configure time) into every SuperGenius/SDK configure, and bypasses the superbuild's tested single-build. The superbuild is the repo's one-build-many-consumers design. |
| Install-tree package config | `FetchContent`/`ExternalProject` from the SuperGenius side | No — duplicates the superbuild entry that already exists (`CommonTargets.cmake:863-919`), double-builds, and would need every dep hint re-specified. |
| Raw imported-location link (`find_library` + `add_library IMPORTED`, wallet-core style at `GeniusSDK/cmake/CommonBuildParameters.cmake:~370-385`) | — (this is the pattern used for TrustWalletCore) | Only justified when a dep ships no CMake package config. sgns-blockstore **does** ship one (`CMakeLists.txt:76-99`) with a namespaced export — use it; the wallet-core pattern loses transitive `p2p::p2p_cid`/`$<LINK_ONLY:miniocpp>` propagation and would hand-maintain link closure. |
| Config fields + env override | Env-only credentials | Env-only is right for headless server deployments — and remains available via the override; but it breaks wallet-asset distribution and the user's blank=disabled config intent. |
| Config fields + env override | `secret_file` path field (read key material from a 0600 file) | Reasonable future addition for hardened server deployments; defer — it is additive (a new optional field + a read step) and v1.1 gains nothing from it. |
| TLS off for loopback s3d, on for remote | Always-on TLS | Loopback HTTP is the tested tier (Tier-2/Tier-3 evidence) and avoids cert plumbing for the primary localhost-s3d deployment; `tls_verify` stays true regardless. Remote-endpoint deployments flip `use_tls`. |

---

## What NOT to Use / NOT to Add

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| Any NEW external dependency (AWS SDK, curl, another S3 client, a new hash lib, a new JSON lib, a threading lib) | v1.0's build decisions already settled this space: minio-cpp was chosen over AWS SDK (v1.0 Out of Scope table: "AWS SDK for C++ — Rejected, libcurl/CRT dependency weight"), and everything else needed is already linked. | The shipped chain: `sgns-blockstore::sgns-blockstore` + its transitive closure. |
| Direct `miniocpp::` / `#include <miniocpp/...>` / cpp-httplib usage in SuperGenius source | Breaks SC2 containment — the entire point of the `S3Client` adapter seam is that no SDK type crosses into consumers (`S3Client.hpp:6-13`; PRIVATE link at `src/CMakeLists.txt:22-27`). SuperGenius should touch only `sgns-blockstore/*` headers. | `S3ClientConfig` + the installed factory (Constraint B fix), `S3BlockStore`, `LocalBlockStore`, `UploadDrainer`. |
| Touching the existing RocksDB `BackupEngine` path or folding cold storage into it | Explicitly out of scope in v1.0 ("Modifying the existing RocksDB BackupEngine path in globaldb.cpp — stays untouched", `v1.0-REQUIREMENTS.md:75`); the two mechanisms are separate by design. | New `blockstore` section + new wrapper; `crdt_backup_config_` untouched. |
| Adding `Remove`/`Delete`/`List` anywhere on the BlockStore path for GC | CORE-05/CORE-06 permanence is guard-tested; "local eviction is never a CRDT deletion" is the project's headline invariant (`BlockStore.hpp:36-45`). GC must be hot-tier eviction (`EvictLocal`) + CRDT-layer policy, never cold-object deletion. | `LocalBlockStore::EvictLocal` + `BlockStoreTooling` enumeration + retention config; CRDT-layer deletions only through existing GlobalDB APIs (and only after the causal-stability spec the v1.0 future-requirements note demands, `v1.0-REQUIREMENTS.md:69`). |
| RocksDB remote-FS / SST-archive integration as the spill mechanism | Explicitly ruled out by the architecture doc (v1.0 Out of Scope: "application-level content-addressed layer instead"). | The BlockStore spill path that shipped. |
| Docker-based or live-internet S3 in CI | Repo CI runners cannot host Docker; hermeticity is a v1.0 hard requirement (`v1.0-REQUIREMENTS.md:80-81`). | `MemoryBlockStore`-faked SuperGenius tests; MinIO-binary opt-in Tier-2 stays in the thirdparty repo's lane. |
| `set(CMAKE_FIND_PACKAGE_PREFER_CONFIG ON)` around the new finds (or moving them inside the libssh2 PREFER_CONFIG window) | The httplib chain's ZLIB find gets re-routed through `ZLIBConfig.cmake` and corrupts the config check — the exact Phase-3 spike failure the superbuild documents (`CommonTargets.cmake:897-915`). | Explicit `*_DIR` hints per the Installation block; leave global PREFER_CONFIG state alone. |
| Versioned `find_package(sgns-blockstore 1.0 CONFIG)` | Not harmful today (`AnyNewerVersion`), but unnecessary; and versioned RocksDB requests are actively harmful (dual-compat, `CMakeLists.txt:13-17`) — keep the whole block version-free for symmetry. | Unversioned `find_package(... CONFIG REQUIRED)`. |
| Linking `minio`/`miniocpp` targets directly into SuperGenius targets | Re-implements the transitive closure by hand and re-couples consumers to SDK targets the adapter seam exists to hide. | Link only `sgns-blockstore::sgns-blockstore`; `$<LINK_ONLY:...>` does the rest. |

---

## Stack Patterns by Variant

**If `blockstore.endpoint`/`bucket`/credentials are blank or the section is absent (default install):**
- Construct nothing; behavior is byte-identical to today. This must be a hard requirement in v1.1 phase 1 (the wrapper degrades to pass-through, or is simply not constructed).

**If s3d runs on the same host (primary deployment):**
- `endpoint=127.0.0.1`, `use_tls=false`, `path_style=true` — the tested Tier-3 lane configuration.
- `local_cache_dir` under the node's `write_base_path_` (where `crdt_config.json` itself lives, `GeniusNode.cpp:554-556`), sibling to but never equal to the GlobalDB directory (D-01: LocalBlockStore owns its own RocksDB instance).

**If the object store is remote:**
- `use_tls=true`, `tls_verify` stays true (default, T-3-02). Credentials via env vars on the server. Expect `ObjectStoreAccepted`-but-not-durable semantics on the drainer's journal advance — the s3d staged-vs-durable finding (`docs/s3d-durability.md`) means retention/GC policy must not assume 200-OK = durable; the `UploadedDurable` transition stays out of scope (drainer never invokes it, `UploadDrainer.hpp:25-31`).

**If building iOS/Android:**
- The superbuild entry is unconditional in `CommonTargets.cmake` (no platform guard at `:837-919`), so mobile superbuild legs should produce the install tree — **but v1.0's CI evidence covers Windows/Linux/OSX only** (`testing-tiers.md:53-57`). Open verification: confirm a mobile superbuild leg actually produces `sgns-blockstore` + `minio-cpp` install trees before relying on it. If a mobile leg is missing, gate the two `find_package` calls behind an option defaulting OFF on `IOS`/`ANDROID` rather than making mobile builds fail — desktop-first is the honest v1.1 posture (cold storage is a node-operator feature; phones are not the first consumer).

---

## Version Compatibility

| Component | Constraint | Verified At |
|-----------|-----------|-------------|
| C++ standard | C++17 on both sides — library sets `CMAKE_CXX_STANDARD 17` (`sgns-blockstore/CMakeLists.txt:6-8`); SuperGenius sets C++17 in `build/CommonCompilerOptions.cmake:8-10`. No 20-ism crosses the installed headers. | OK — no action |
| Boost.Outcome policy interplay | Library results are `libp2p::outcome::basic_result` with **`policy::terminate`** (deliberate deviation: `BlockStatus` is a plain struct, boost's default `exception_ptr_rethrow` observers can't instantiate for it — `Cid.hpp:25-37`). SuperGenius's own `outcome::result` aliases are a different vendored namespace instance. Practical rules for consumer code: (1) always guard with `has_value()`/`if (!res)` before `.value()`/`.error()` — unchecked access **terminates the node process**; (2) convert to SuperGenius outcome types by extracting value/error, never by template reinterpretation. | `Cid.hpp:18-37` |
| libp2p CID type | `sgns::blockstore::Cid` IS `libp2p::multi::ContentIdentifier` (D-05, zero-conversion alias, `Cid.hpp:39-46`) — but see Constraint A: the CRDT path's CIDs are blake2b-256 and are rejected until the widening lands. | `Cid.hpp:66-79`, `cid.cpp:129-134` |
| libp2p version skew | Library was built against the superbuild's libp2p (9.x line); consumer resolves the **same** install tree libp2p (`CommonBuildParameters.cmake:240`), so no skew is possible in-repo. External consumers need a libp2p providing `p2p::p2p_cid`. | OK |
| RocksDB dual-compat | 9.4 (superbuild) / 11.1.2 (standalone) both accepted — no version argument anywhere (`sgns-blockstore/CMakeLists.txt:13-17`); pimpl'd LocalBlockStore keeps `rocksdb::*` out of installed headers (`LocalBlockStore.hpp:63-69`). SuperGenius links the same install-tree RocksDB it always has. | OK |
| minio-cpp chain pins | minio-cpp v1.0.0; cpp-httplib v0.53.1 + inih r58 pinned by upstream's own `miniocpp-deps.cmake`; pugixml v1.16; consumer reuses them from the install tree — **never re-resolve or bump independently** or the ABI silently splits. | `CommonTargets.cmake:824-860` |
| MSVC runtime | SuperGenius forces `/MT`-family (`CMAKE_MSVC_RUNTIME_LIBRARY MultiThreaded$<$<CONFIG:Debug>:Debug>`, `SuperGenius/build/Windows/CMakeLists.txt:31`); superbuild built the lib with the same static-runtime discipline (`Boost_USE_STATIC_RUNTIME ON`, `OPENSSL_MSVC_STATIC_RT ON`). Both sides must keep matching — they do today; nothing to add. | OK |
| CMake minimum | 3.20 (library) vs 3.22 (SuperGenius/GeniusSDK platform files) — no conflict; consumer requirement is just `find_package CONFIG`. | OK |
| sgns-blockstore config version | `VERSION 1.0.0 COMPATIBILITY AnyNewerVersion` (`CMakeLists.txt:87-91`) — future additive versions satisfy unversioned requests. | OK |

---

## Sources

All primary sources verified in-tree on 2026-10-22 (confidence HIGH unless noted):

- `thirdparty/sgns-blockstore/CMakeLists.txt` — install rules, namespaced export, package config + version file (`:57-99`); httplib missing-imported-target failure note (`:23-33`); RocksDB no-version dual-compat note (`:13-17`)
- `thirdparty/sgns-blockstore/src/CMakeLists.txt` — `PUBLIC p2p::p2p_cid / PUBLIC RocksDB::rocksdb / PRIVATE miniocpp::miniocpp` (`:20-27`)
- `thirdparty/sgns-blockstore/cmake/config.cmake.in` — only `find_dependency(RocksDB CONFIG)` (`:1-6`)
- `thirdparty/sgns-blockstore/include/sgns-blockstore/` — `Cid.hpp` (outcome/terminate policy `:18-37`, CID alias `:39-46`, sha-256-only `:66-79`), `BlockStore.hpp` (D-08 blake2b boundary `:46-56`), `S3Client.hpp` (installed seam, config struct `:58-72`, never-log `:68-69`), `S3BlockStore.hpp` (key layout/Open `:30-52`), `LocalBlockStore.hpp` (own-instance D-01 `:72-97`), `UploadDrainer.hpp` (drain semantics `:25-104`)
- `thirdparty/sgns-blockstore/src/MinioS3Client.hpp` — impl header not installed (`:1-16`, listed in `src/`)
- `thirdparty/sgns-blockstore/docs/testing-tiers.md` — tier table, gate env vars, CI lane invocation (`:15-58`)
- `thirdparty/build/CommonTargets.cmake` — minio-cpp entry (`:824-860`), nlohmann_json datadir layout note (`:806-808`), pugixml entry (`:809-817`), sgns-blockstore entry + config dir (`:863-919`), ZLIB/PREFER_CONFIG trap note (`:897-915`)
- `SuperGenius/build/CommonCompilerOptions.cmake` — `THIRDPARTY_BUILD_DIR` resolution + tarball fallback (`:219-282`), C++17 (`:8-10`)
- `SuperGenius/build/CommonBuildParameters.cmake` — RocksDB (`:119-121`), libp2p (`:240`), ipfs-lite-cpp (`:347`) consumer patterns
- `SuperGenius/build/Windows/CMakeLists.txt` — `/MT` runtime (`:31`), platform entry includes `../CommonBuildParameters.cmake` (`:75`)
- `SuperGenius/src/account/GeniusNode.cpp` — `LoadCrdtConfig` pattern (`:552-610`)
- `SuperGenius/src/crdt/globaldb/globaldb.cpp` — datastore construction seam (`:322-344`); `globaldb.hpp` — `New(... datastore = nullptr ...)` injection param (`:52-63`)
- `thirdparty/ipfs-lite-cpp/ipfs_lite/ipfs/datastore.hpp` — `IpfsDatastore` interface (`:15+`); `primitives/cid/cid.cpp` — `getCidOf` = blake2b-256 + DAG_CBOR (`:129-134`)
- `SuperGenius/src/crdt/CMakeLists.txt` — `crdt_*` target/link/`supergenius_install` pattern
- `GeniusSDK/build/CommonBuildParameters.cmake` — includes `../../cmake/CommonBuildParameters.cmake` (`:1-5`); `GeniusSDK/cmake/CommonBuildParameters.cmake` — SDK-side dep-resolution variant (rocksdb `:110-113`, wallet-core raw-imported pattern `:~370-385`)
- `GeniusWallet/assets/crdt_config.json` — current 4-field schema (asset-distribution parity note)
- `supergenius-sharded-ipld-cache-architecture.md` — credential guidance (`:539`)
- `.planning/workstreams/rocksdb-backup/milestones/v1.0-REQUIREMENTS.md` — Future Requirements incl. the exact deferred wiring (`:58-69`) and Out of Scope table (`:71-81`)
- `.planning/workstreams/rocksdb-backup/STATE.md` — v1.1 milestone context (`:1-20`)
- Mobile superbuild leg coverage: **not verified** (MEDIUM) — flagged in *Stack Patterns by Variant* as the one open build question

---
*Stack research for: SuperGenius cold-storage integration (rocksdb-backup v1.1)*
*Researched: 2026-10-22*
