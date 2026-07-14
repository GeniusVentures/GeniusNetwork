# Phase 3: Consumer Integration — Research

**Phase:** 03-Consumer-Integration
**Created:** 2026-07-09

---

## Research Summary

Phase 2 applied 10 thread-safety fixes to ipfs-bitswap-cpp. Of these, only **2 changes affect consumer code** at the semantic level, and both require **zero code changes** — verification by code review is sufficient:

| Phase 2 Change | Consumer Impact | Code Changes Needed |
|---------------|-----------------|---------------------|
| GetBlock() `const` removal | None — zero production calls to GetBlock() | **None** |
| PublishFile/PublishDirectory → io_context dispatch | IPFSSaver callbacks now run on io_context instead of detached std::thread | **None** (callbacks are io_context-safe) |
| setCacheDir/getCacheDir mutex guard | None — already called before async operations begin | **None** |
| SetMaxPeerAttempts/SetPeerFailureThreshold → atomics | None — zero production calls to these setters | **None** |
| ContentRequestContext strand confinement | None — internal to Bitswap | **None** |
| BitswapRequestContext timer race fix | None — internal to Bitswap | **None** |
| Callback-invocation-under-lock fix (C-7) | None — internal to Bitswap | **None** |

**Verdict:** Phase 3 is a **verification-only phase**. No consumer code changes are required. The phase delivers code review confirmation, documentation updates (CONCURRENCY-MAP.md extension + Doxygen annotations), and one-line build verification.

---

## Consumer Call Site Analysis

### SuperGenius (CONS-01, CONS-03)

| Method | File:Line | Phase 2 Impact | Thread Context | Action Needed |
|--------|-----------|----------------|----------------|---------------|
| `Bitswap()` constructor | `GeniusNode.cpp:1308` | None | Main init thread | **None** — constructor unchanged |
| `bitswap_->initialize()` | `GeniusNode.cpp:1310` | None | Main init thread | **None** |
| `bitswap_->setCacheDir()` | `GeniusNode.cpp:1314` | Now mutex-guarded (`mutexCacheDir_`) | Main init thread (single-threaded init phase) | **None** — called before any async operations begin, before Bitswap is shared with other components |
| `FileManager::setBitswap()` | `GeniusNode.cpp:1317` | Reads `getCacheDir()` under mutex | Main init thread | **None** — synchronous init sequence, `getCacheDir()` read is mutex-safe |
| `bitswap->HasBlock()` | `GeniusNode.cpp:797` | None (already mutex-guarded pre-Phase-2) | Processing service callback thread | **None** — `mutexBlockStore_` + `mutexDiskIndex_` protection unchanged |
| `bitswap->RequestContent()` | `GeniusNode.cpp:802` | None (API unchanged) | Processing service callback thread | **None** — callback fires on libp2p thread (unchanged contract) |
| `bitswap_->unpersistBlock()` | `GeniusNode.cpp:3432` | None (already mutex-guarded pre-Phase-2) | GC maintenance thread | **None** — `mutexDiskIndex_` protection unchanged |
| `m_bitswap->HasBlock()` | `processing_subtask_queue_accessor_impl.cpp:564` | None (already mutex-guarded pre-Phase-2) | Processing worker thread | **None** |
| `setBitswap()` propagation | `processing_service.hpp:70` → `processing_node.hpp:69` → `SubTaskQueueAccessor` | None | Main init or processing thread | **None** — shared_ptr propagation unchanged |

**CRDT layer (CONS-03):** The CRDT layer (`graphsync_dagsyncer.cpp`, `crdt_datastore.cpp`, `pubsub_broadcaster_ext.cpp`) calls `HasBlock()` indirectly through `dagSyncer_->HasBlock(cid)` — this is a different interface (graphsync's HasBlock, not Bitswap's HasBlock). Zero CRDT code directly references Bitswap. Bitswap is used through the processing layer's data availability checks (`SubTaskQueueAccessor`), which are mutex-guarded. **No CRDT-specific verification needed.**

### AsyncIOManager (CONS-02, CONS-04)

| Method | File:Line | Phase 2 Impact | Thread Context | Action Needed |
|--------|-----------|----------------|----------------|---------------|
| `externalBitswap_->PublishFile()` | `IPFSSaver.cpp:107` | **Callback now fires on Bitswap io_context** instead of detached std::thread | IPFSSaver internal thread → callback on Bitswap io_context | **None** — callback is io_context-safe (see analysis below) |
| `externalBitswap_->PublishDirectory()` | `IPFSSaver.cpp:190` | **Callback now fires on Bitswap io_context** instead of detached std::thread | IPFSSaver internal thread → callback on Bitswap io_context | **None** — callback is io_context-safe (see analysis below) |
| `externalBitswap_ = bitswap` | `IPFSSaver.cpp:32` | None | Init/FileManager thread | **None** — shared_ptr assignment, thread-safe |
| `cacheDir_ = bitswap->getCacheDir()` | `FileManager.cpp:249` | Now mutex-guarded read | Main init thread (via GeniusNode init chain) | **None** — synchronous init sequence |
| `bitswap_->RequestContent()` | `IPFSCommon.cpp:185` | None (API unchanged) | io_context (via `RequestBlockMain`) | **None** — callback contract unchanged |
| `Bitswap()` standalone construction | `IPFSCommon.cpp:76` | None | io_context (IPFSDevice constructor) | **None** — constructor unchanged |
| `Bitswap()` external construction | `IPFSCommon.cpp:85-87` | None | io_context (IPFSDevice constructor) | **None** — constructor unchanged |
| `IPFSLoader::setBitswap()` | `IPFSLoader.cpp:207-211` | None | Init/FileManager thread | **None** — shared_ptr assignment, stores in member |

---

## PublishFile/PublishDirectory Callback Safety Analysis

**Context:** Phase 2 replaced `std::thread(...).detach()` with `boost::asio::post(context_, ...)` in `PublishFile()` and `PublishDirectory()`. Callbacks now fire on Bitswap's internal io_context instead of detached threads. This is the **only** consumer-facing behavioral change.

**IPFSSaver PublishFile callback (IPFSSaver.cpp:109-141) operations:**
1. `std::filesystem::remove(tempFilePath)` — Fast, stateless filesystem operation. Safe on io_context.
2. `libp2p::multi::ContentIdentifierCodec::toString(result.value())` — Pure utility function, immutable parameters. Thread-safe.
3. `m_logger->info(...)` / `m_logger->error(...)` — spdlog is inherently thread-safe. Safe on any thread context.
4. `*save_location = "ipfs://" + cidString.value()` — `save_location` is captured as `std::shared_ptr<std::string>` (decremented, not dangling). String assignment is safe.
5. `boost::asio::post(*ioc, [handle_write, ioc]() { handle_write(ioc); })` — Posts completion notification back to IPFSSaver's own io_context. Safe.

**IPFSSaver PublishDirectory callback (IPFSSaver.cpp:192-221):** Identical pattern — same operations, same safety profile.

**Capture semantics:** Both callbacks use `[=]` value capture. Captured values:
- `tempFilePath` / `tempDirPath` — `std::string`, captured by value, safe
- `filePaths[0]` — `std::string`, captured by value, safe
- `save_location` — `std::shared_ptr<std::string>`, shared ownership, safe
- `handle_write` — function object, safe
- `ioc` — `shared_ptr<boost::asio::io_context>`, shared ownership, safe

**Conclusion:** The IPFSSaver callbacks are safe running on io_context. In fact, io_context dispatch is **strictly better** than detached threads because:
1. Publish operations are serialized (one at a time on the io_context strand)
2. The Bitswap object's lifetime (via `shared_from_this()`) ensures no use-after-free
3. Detached threads could run concurrently and potentially outlive Bitswap's destruction

---

## GetBlock() const Removal — Verification

**Zero production code calls `GetBlock()` directly.** Confirmed via exhaustive grep:

```
grep pattern: bitswap->GetBlock | bitswap_->GetBlock | m_bitswap->GetBlock | externalBitswap_->GetBlock
  SuperGenius/src:   0 matches
  AsyncIOManager/src: 0 matches
  (all .cpp + .hpp files)
```

No `const shared_ptr<const Bitswap>` references found in any consumer code. The `const` removal causes no compilation errors.

---

## setCacheDir/getCacheDir Mutex Guard — Verification

**GeniusNode (SuperGenius):**
- `bitswap_->setCacheDir(fullCachePath)` at `GeniusNode.cpp:1314`
- Called inside `InitSubSystems()` → during main-thread initialization, **before** any async operations begin
- Bitswap is not yet shared with other components (FileManager::setBitswap follows on line 1317, processing service init follows later)
- Even if called concurrently, the mutex now provides proper serialization

**FileManager (AsyncIOManager):**
- `cacheDir_ = bitswap->getCacheDir()` at `FileManager.cpp:249`
- Called from `FileManager::setBitswap()` which is called synchronously from `GeniusNode::InitSubSystems()` at line 1317
- Happens during single-threaded init phase before any async operations
- Mutex addition makes this call thread-safe in any future concurrent context

---

## Build/Linkage Analysis

### ipfs-bitswap-cpp in the build graph

```
CommonTargets.CMake:488-522 — ExternalProject_Add(ipfs-bitswap-cpp ...)
  DEPENDS: Microsoft.GSL spdlog libp2p Boost GTest ipfs-lite-cpp
  Config dir: ${CMAKE_CURRENT_BINARY_DIR}/ipfs-bitswap-cpp/lib/cmake/ipfs-bitswap-cpp

AsyncIOManager (CommonTargets.CMake:660-692):
  CMAKE_CACHE_ARGS: -Dipfs-bitswap-cpp_DIR:PATH=${_FINDPACKAGE_IPFS_BITSWAP_CONFIG_DIR}
  DEPENDS: ... ipfs-bitswap-cpp ...
```

### SuperGenius linkage

```
account/CMakeLists.txt:
  genius_node links: ipfs-bitswap-cpp (line 98, PRIVATE)

processing/CMakeLists.txt:
  processing_service links: ipfs-bitswap-cpp (line 65, PRIVATE)
```

### AsyncIOManager linkage

```
AsyncIOManager/CMakeLists.txt:
  find_package(ipfs-bitswap-cpp CONFIG REQUIRED) — line 47
  include_directories(${ipfs-bitswap-cpp_INCLUDE_DIR}) — line 48
```

### Phase 2 changes — no build impact

Phase 2 made internal-only changes:
- Added `std::mutex mutexCacheDir_` member → bitswap.hpp
- Converted `maxPeerAttempts_`, `peerFailureThreshold_` to `std::atomic` → bitswap.hpp  
- Replaced `std::thread(...).detach()` with `boost::asio::post(context_, ...)` → bitswap.cpp
- Added `contentRequestsMutex_` to ContentRequestContext → bitswap.hpp
- Removed `const` from `GetBlock()` → bitswap.hpp, bitswap.cpp

No new source files. No new dependencies. No CMake or build system changes needed in consumers.

**Verdict:** Zero build changes needed for SuperGenius or AsyncIOManager.

---

## Documentation Scope (DOCS-02)

Per decisions D-07 and D-08 in 03-CONTEXT.md:

### 1. CONCURRENCY-MAP.md — Consumer Contract Section (D-07)
Extend the existing `CONCURRENCY-MAP.md` with a new section after "Thread Entry-Point Inventory":

```
## Phase 3: Consumer Contract

Method-by-method table for consumer-side thread-safety:
| Method | Caller Thread Requirement | Callback Thread | Mutex/Atomic Guarantee | Phase 2 Change |
|---|---|---|---|---|
| PublishFile | Any | Bitswap io_context (was: detached std::thread) | mutexBlockStore_ | io_context::post replaces detached thread |
| PublishDirectory | Any | Bitswap io_context (was: detached std::thread) | mutexBlockStore_ | io_context::post replaces detached thread |
| HasBlock | Any | N/A | mutexBlockStore_ + mutexDiskIndex_ | Unchanged |
| RequestContent | Any | libp2p thread (success) / io_context (timeout) | mutexContentRequests_ | Unchanged |
| GetBlock | Any | N/A | mutexBlockStore_ + mutexDiskIndex_ | const removed |
| setCacheDir | Called once before async ops begin | N/A | mutexCacheDir_ | Added mutex guard |
| getCacheDir | Caller's thread | N/A | mutexCacheDir_ | Added mutex guard |
| SetMaxPeerAttempts | Any | N/A | std::atomic | Plain → atomic |
| SetPeerFailureThreshold | Any | N/A | std::atomic | Plain → atomic |
```

### 2. Doxygen @note Annotations (D-08)
Add inline annotations in `bitswap.hpp` for methods whose contract changed:

- `PublishFile` (line ~237): `@note Callback fires on Bitswap's internal io_context. Consumer callbacks must not block the io_context thread.`
- `PublishDirectory` (line ~238): same note
- `getCacheDir` (line ~249): `@note Returns a copy of the cache directory under mutex protection. Thread-safe for concurrent calls.`
- `setCacheDir` (line ~248): `@note Sets cache directory under mutex protection. Call once before starting async operations for deterministic behavior.`

---

## Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|-----------|--------|------------|
| IPFSSaver callback blocks io_context | Very Low | Medium — blocked io_context delays all publish operations | Callback operations are trivial (remove temp file, log, post). No blocking I/O or computation. |
| getCacheDir() race during init | None | N/A | Called synchronously in single-threaded init phase before Bitswap is shared |
| Consumer added GetBlock() call since Phase 1 | None | N/A | Exhaustive grep confirms zero GetBlock() calls in production code |
| Build break on non-Windows platform | Low | Low — CI catches it, not a phase blocker | Standard C++17 changes (mutex, atomic, io_context::post) — zero platform-specific code |
| Missed consumer call site | Low | Medium — compilation error would be immediate | All public Bitswap methods traced through SuperGenius and AsyncIOManager codebase |

---

## Validation Architecture (for Nyquist Implementation)

The Phase 3 plan should use a checklist-based verification architecture with 5 validation gates:

### V-1: Build Verification
- **Action:** Run Windows build (already confirmed passing). Check CI for Linux/macOS/iOS/Android builds.
- **Pass condition:** All platforms compile and link with zero errors.
- **Evidence:** Build log showing `ipfs-bitswap-cpp` target succeeds, consumer targets (genius_node, processing_service, AsyncIOManager) link successfully.

### V-2: PublishFile/PublishDirectory Callback Audit
- **Action:** Code review of `IPFSSaver.cpp:107-141` and `IPFSSaver.cpp:190-221`.
- **Pass condition:** All callback operations confirmed safe on io_context — no blocking I/O, no long computation, no lock acquisition.
- **Evidence:** Review checklist: temp file cleanup (fast), logging (async-safe), string operations (safe), asio::post fallback (safe).

### V-3: GetBlock() const Removal Impact
- **Action:** Grep all consumer code for GetBlock calls through any Bitswap reference pattern.
- **Pass condition:** Zero matches found (already confirmed).
- **Evidence:** Grep output showing 0 results in SuperGenius/src and AsyncIOManager.

### V-4: setCacheDir Thread Safety
- **Action:** Code review of GeniusNode.cpp:1314 and FileManager.cpp:249 call sequences.
- **Pass condition:** Both call sites confirmed to execute before any async Bitswap operations begin (single-threaded init phase).
- **Evidence:** InitSubSystems() call sequence analysis — setCacheDir (1314) → setBitswap (1317) → all async start.

### V-5: Documentation Completeness
- **Action:** Update CONCURRENCY-MAP.md with consumer contract section + add Doxygen @notes to bitswap.hpp.
- **Pass condition:** Document updated per D-07/D-08 specification.
- **Evidence:** File diff showing new sections/comments.

---

## References Checked

### Planning Documents
- `.planning/REQUIREMENTS.md` — CONS-01..04, DOCS-02 requirements
- `.planning/ROADMAP.md` — Phase 3 success criteria (4 items)
- `.planning/STATE.md` — Current phase tracking
- `.planning/phases/03-consumer-integration/03-CONTEXT.md` — Phase 3 decisions D-01..D-10

### Prior Phase Artifacts
- `.planning/phases/01-audit/CONCURRENCY-MAP.md` — Full audit (10 findings, 503 lines)
- `.planning/phases/02-fix-test/02-CONTEXT.md` — Phase 2 decisions D-01..D-10

### Bitswap API Surface
- `thirdparty/ipfs-bitswap-cpp/src/bitswap.hpp` — Full class definition, 457 lines, 7 mutex domains

### Consumer Source Files (all read)
- `SuperGenius/src/account/GeniusNode.cpp` — Lines 797, 802, 1308-1317, 3432
- `SuperGenius/src/processing/processing_subtask_queue_accessor_impl.cpp` — Line 564
- `SuperGenius/src/processing/processing_service.hpp` — Line 70, member m_bitswap
- `SuperGenius/src/processing/processing_node.hpp` — Line 69, member m_bitswap
- `thirdparty/AsyncIOManager/src/IPFSSaver.cpp` — Lines 107, 190 (PublishFile/Directory)
- `thirdparty/AsyncIOManager/src/IPFSLoader.cpp` — Line 207 (setBitswap)
- `thirdparty/AsyncIOManager/src/IPFSCommon.cpp` — Lines 76, 85-87, 185
- `thirdparty/AsyncIOManager/src/FileManager.cpp` — Lines 244-269

### Build Files
- `thirdparty/build/CommonTargets.CMake` — Lines 488-522 (ipfs-bitswap-cpp), 660-692 (AsyncIOManager)
- `SuperGenius/src/account/CMakeLists.txt` — Line 98 (ipfs-bitswap-cpp link)
- `SuperGenius/src/processing/CMakeLists.txt` — Line 65 (ipfs-bitswap-cpp link)
- `thirdparty/AsyncIOManager/CMakeLists.txt` — Line 47 (find_package)

---

*Research completed: 2026-07-09*
